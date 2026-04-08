# frozen_string_literal: true

module Services
  module Mailbox
    class Runner
      TASK_NAME      = 'mailbox'
      MAX_ITERATIONS = 25

      SYSTEM_PROMPT = <<~TEXT
        You are an agent solving the AG3NTS task "mailbox".

        Goal: Search a mailbox via the zmail API and extract three pieces of information:
        - date: the date (YYYY-MM-DD) the security department plans to attack our power plant
        - password: a password found somewhere in the mailbox
        - confirmation_code: a ticket confirmation code in the format SEC- followed by exactly 32 characters (36 chars total)

        The mailbox belongs to a System operator. Wiktor from the resistance movement (vik4tor@proton.me)
        sent a message reporting on our activities. There may be multiple relevant emails.
        The mailbox is active — new messages may arrive while you are working.

        WORKFLOW:
        1. Call call_zmail_api with action="help" to discover all available API actions and their parameters.
        2. Search for Wiktor's email: action="search", params={"query":"from:proton.me"}
        3. Search for the password email: action="search", params={"query":"hasło"} (Polish for password)
        4. Search for confirmation codes: action="search", params={"query":"SEC-"}
        5. For each relevant message, fetch the FULL body by IDs (pass array of messageIDs in "ids" field of params).
        6. IMPORTANT: If there are correction emails (subject contains "zły kod" or "poprawny"), always read those
           to get the corrected confirmation code — the first code sent may have a typo.
        7. Once you have all three values confirmed, call submit_answer.

        RULES:
        - Always fetch full message bodies — use action="getMessages" with params={"ids": ["messageID1", ...]}
        - The confirmation_code must be EXACTLY SEC- + 32 characters = 36 characters total. Count carefully.
        - If there is a correction email saying the previous code was wrong, use the CORRECTED code.
        - Date must be in YYYY-MM-DD format.
        - The password is in Polish emails — search for "hasło" not "password".
        - If submit_answer returns error -970 (Invalid payload), the confirmation_code length is wrong (not 36 chars).
        - If submit_answer returns error -960 (Incorrect data), one of the values is factually wrong.
        - Do not submit until you have verified all three values from actual email content.
      TEXT

      def initialize(llm_client:, tool_executor:, logger: $stdout)
        @llm_client    = llm_client
        @tool_executor = tool_executor
        @logger        = logger
      end

      def call
        messages = [{ role: 'system', content: SYSTEM_PROMPT },
                    { role: 'user',
                      content: 'Start by calling call_zmail_api with action="help" to learn the available API actions, then proceed to search for the required information.' }]

        final_result = nil

        MAX_ITERATIONS.times do |i|
          iteration = i + 1
          log("--- iteration #{iteration}/#{MAX_ITERATIONS} ---")

          response = @llm_client.chat_with_tools(messages: messages, tools: tool_definitions)
          messages << build_assistant_message(response)

          tool_calls = Array(response['tool_calls'])
          content    = response['content'].to_s.strip

          log("content: #{content[0, 200]}") unless content.empty?
          log("tool_calls: #{tool_calls.size}") if tool_calls.any?

          if tool_calls.empty?
            log('no tool calls — agent finished without submitting')
            break
          end

          tool_calls.each do |tc|
            tool_name  = tc.dig('function', 'name').to_s
            arguments  = parse_arguments(tc.dig('function', 'arguments'))
            log("tool: #{tool_name}(#{arguments.reject { |k, _| k == 'params' }.to_json})")

            result = @tool_executor.call(name: tool_name, arguments: arguments)
            log("result: #{JSON.generate(result)[0, 300]}")

            messages << {
              role: 'tool',
              tool_call_id: tc['id'],
              content: JSON.generate(result)
            }

            final_result = result if tool_name == 'submit_answer' && result[:verification]
          end

          break if final_result
        end

        raise 'Mailbox agent did not submit an answer within the iteration limit' if final_result.nil?

        final_result
      end

      private

      def build_assistant_message(response)
        msg = { role: response.fetch('role', 'assistant') }
        content    = response['content']
        tool_calls = Array(response['tool_calls'])
        msg[:content]    = content    unless content.nil?
        msg[:tool_calls] = tool_calls unless tool_calls.empty?
        msg
      end

      def parse_arguments(raw)
        return {} if raw.to_s.strip.empty?

        JSON.parse(raw)
      rescue JSON::ParserError => e
        raise ArgumentError, "Tool arguments are not valid JSON: #{e.message}"
      end

      def log(message)
        @logger.puts("[mailbox] #{message}")
      end

      def tool_definitions
        [
          {
            type: 'function',
            function: {
              name: 'call_zmail_api',
              description: <<~DESC.strip,
                Call the zmail mailbox API. Use action="help" first to discover all available actions.
                Then use the discovered actions to search messages (e.g. action="search" with query param),
                get inbox listing, or fetch full message bodies by ID.
                Pass any additional action-specific parameters in the "params" object.
              DESC
              parameters: {
                type: 'object',
                additionalProperties: false,
                required: ['action'],
                properties: {
                  action: {
                    type: 'string',
                    description: 'The zmail API action to call (e.g. "help", "getInbox", "search", "getMessage")'
                  },
                  params: {
                    type: 'object',
                    description: 'Additional action-specific parameters (e.g. { "query": "from:proton.me", "page": 1 } or { "id": "msg-id" })',
                    additionalProperties: true
                  }
                }
              }
            }
          },
          {
            type: 'function',
            function: {
              name: 'submit_answer',
              description: 'Submit the final answer once you have found all three values from the mailbox. Only call this when you have confirmed all three values from actual email content.',
              parameters: {
                type: 'object',
                additionalProperties: false,
                required: %w[date password confirmation_code],
                properties: {
                  date: {
                    type: 'string',
                    description: 'Date of the planned attack in YYYY-MM-DD format'
                  },
                  password: {
                    type: 'string',
                    description: 'The password found in the mailbox'
                  },
                  confirmation_code: {
                    type: 'string',
                    description: 'Ticket confirmation code: SEC- followed by exactly 32 characters (36 chars total)'
                  }
                }
              }
            }
          }
        ]
      end
    end
  end
end

