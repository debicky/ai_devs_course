# frozen_string_literal: true

module Services
  module Shellaccess
    class Runner
      TASK_NAME      = 'shellaccess'
      MAX_ITERATIONS = 25

      SYSTEM_PROMPT = <<~PROMPT
        You are an agent with shell access to a remote Linux server.
        Output limit is 4096 bytes. Execute ONE command at a time.

        MISSION: Find when and where Rafał's body was found. Return JSON with date ONE DAY BEFORE.

        DATA in /data/:
        - time_logs.csv: semicolon-separated: date;description;location_id;entry_id
        - locations.json: array of {location_id, name}
        - gps.json: array of {latitude, longitude, type, location_id, entry_id}

        IMPORTANT: The name is "Rafał" (Polish ł).

        CRITICAL: Do NOT use the pipe character ANYWHERE in commands.
        - Shell pipes get stripped.
        - Regex alternation pipes get stripped too.
        Use grep -e for multiple patterns instead.

        STEPS:

        1. Search for body/death entries. The last Rafał entry (2024-10-29) is about
           disappearance, NOT finding the body. You need a DIFFERENT entry.
           Try: grep -i "ciało" /data/time_logs.csv

        2. Extract from matching line: DATE (field 1), LOCATION_ID (field 3), ENTRY_ID (field 4)

        3. Look up city by LOCATION_ID. Use -A 1 to get the name on the next line:
             grep -A 1 '"location_id": LOCATION_ID' /data/locations.json
           This returns the location_id line and the name line right after it.

        4. Look up coordinates by ENTRY_ID. Use -B 5 (latitude/longitude come before entry_id):
             grep -n -B 5 "ENTRY_ID" /data/gps.json

        5. Subtract one day from DATE manually.

        6. YOU MUST call execute_shell with the echo command. Do NOT just write the JSON.
           Call: echo '{"date":"YYYY-MM-DD","city":"CITY_NAME","longitude":LNG,"latitude":LAT}'
           You MUST use the execute_shell tool for this step. Never skip it.

        CRITICAL:
        - Date must be ONE DAY BEFORE the body was found
        - longitude and latitude must be numbers
        - ALWAYS use execute_shell for the final echo — never skip the tool call
        - Use grep -A 1 with exact location_id pattern for city lookup
        - Use grep -B 5 for GPS lookup
        - If "Invalid value in field" error = your data is WRONG, search again
      PROMPT

      def initialize(llm_client:, tool_executor:, logger: $stdout)
        @llm_client    = llm_client
        @tool_executor = tool_executor
        @logger        = logger
      end

      def call
        messages = [
          { role: 'system', content: SYSTEM_PROMPT },
          { role: 'user', content: 'Start with step 1. Run: grep -i "ciało" /data/time_logs.csv' }
        ]

        final_result = nil

        MAX_ITERATIONS.times do |i|
          iteration = i + 1
          log("--- iteration #{iteration}/#{MAX_ITERATIONS} ---")

          response  = @llm_client.chat_with_tools(messages: messages, tools: tool_definitions)
          messages << build_assistant_message(response)

          tool_calls = Array(response['tool_calls'])
          content    = response['content'].to_s.strip

          log("content: #{content[0, 300]}") unless content.empty?
          log("tool_calls: #{tool_calls.size}") if tool_calls.any?

          if tool_calls.empty?
            log('No tool calls — agent finished')
            break
          end

          tool_calls.each do |tc|
            tool_name = tc.dig('function', 'name').to_s
            arguments = parse_arguments(tc.dig('function', 'arguments'))
            log("tool: #{tool_name}(#{arguments.to_json})")

            result = @tool_executor.call(name: tool_name, arguments: arguments)
            result_json = JSON.generate(result)
            log("result: #{result_json[0, 500]}")

            messages << {
              role: 'tool',
              tool_call_id: tc['id'],
              content: result_json
            }

            output = result[:output].to_s
            if output.include?('FLG:')
              log('FLAG DETECTED in output!')
              final_result = { flag: output, iteration: iteration }
            end
          end

          break if final_result
        end

        raise "Shellaccess agent did not find the answer within #{MAX_ITERATIONS} iterations" if final_result.nil?

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

      def tool_definitions
        [
          {
            type: 'function',
            function: {
              name: 'execute_shell',
              description: 'Execute a shell command on the remote Linux server. ' \
                           'Available tools: ls, cat, head, tail, grep, find, wc, jq, echo, date. ' \
                           'The /data/ directory contains the log archive to search. ' \
                           'Returns { "output": "..." } with command stdout/stderr.',
              parameters: {
                type: 'object',
                additionalProperties: false,
                required: ['cmd'],
                properties: {
                  cmd: {
                    type: 'string',
                    description: 'Shell command to execute, e.g. "ls /data/" or "grep -r Rafał /data/"'
                  }
                }
              }
            }
          }
        ]
      end

      def log(message)
        @logger.puts("[shellaccess] #{message}")
      end
    end
  end
end
