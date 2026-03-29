# frozen_string_literal: true

module Services
  module Firmware
    class Runner
      TASK_NAME      = 'firmware'
      MAX_ITERATIONS = 40

      SYSTEM_PROMPT = <<~TEXT
        You are an agent operating inside a restricted Linux virtual machine via a shell API.

        MISSION: Run `/opt/firmware/cooler/cooler.bin admin1` and submit the ECCS- code.

        IMPORTANT: The /opt/firmware/cooler/ directory is a WRITABLE VOLUME.
        Changes to files there persist across reboots. Previous runs corrupted settings.ini.
        You MUST explicitly fix all three lines. Do NOT reboot (it doesn't help here).

        TARGET settings.ini state:
          [main]
          SAFETY_CHECK=pass          ← line 2 (was corrupted to "admin1" — must reset to "pass")
          power_plant_id=PWR6132PL   ← line 3 (do not touch)
                                     ← line 4 empty
          [test_mode]
          enabled=false              ← line 6 (must be false)
                                     ← line 7 empty
          [cooling]
          power_percent=100          ← line 9 (do not touch)
          enabled=true               ← line 10 (must be true)

        EXACT STEPS — execute in this order, no deviation:
        1. Reset SAFETY_CHECK (line 2):
           execute_shell("editline /opt/firmware/cooler/settings.ini 2 SAFETY_CHECK=pass")
        2. Disable test mode (line 6):
           execute_shell("editline /opt/firmware/cooler/settings.ini 6 enabled=false")
        3. Enable cooling (line 10):
           execute_shell("editline /opt/firmware/cooler/settings.ini 10 enabled=true")
        4. Remove the lock file:
           execute_shell("rm /opt/firmware/cooler/cooler-is-blocked.lock")
        5. Verify settings.ini looks correct:
           execute_shell("cat /opt/firmware/cooler/settings.ini")
        6. Run the binary:
           execute_shell("/opt/firmware/cooler/cooler.bin admin1")
        7. Submit the ECCS- code:
           submit_answer(confirmation: "<exact code>")

        IF step 6 still fails:
        - "SAFETY_CHECK is not set" → cat settings.ini, recheck line 2 value, editline to fix it
        - "test mode must be disabled" → editline line 6 enabled=false again
        - "cooling not enabled" → editline line 10 enabled=true again
        - lock file → rm lock file again
        - DO NOT use reboot — it does not help for this writable volume

        SECURITY RULES:
        - Do NOT access /etc, /root, or /proc/
        - Do not touch .env, storage.cfg, or logs/ (gitignored)
        - You are a regular user, not root
        - Never guess the ECCS- code — only submit the exact output from the binary
      TEXT

      def initialize(llm_client:, tool_executor:, logger: $stdout)
        @llm_client    = llm_client
        @tool_executor = tool_executor
        @logger        = logger
      end

      def call
        messages = [
          { role: 'system', content: SYSTEM_PROMPT },
          { role: 'user',
            content: 'Execute the steps now: 1) editline line 2 SAFETY_CHECK=pass, 2) editline line 6 enabled=false, 3) editline line 10 enabled=true, 4) rm lock file, 5) cat to verify, 6) run binary, 7) submit ECCS- code.' }
        ]

        final_result = nil

        MAX_ITERATIONS.times do |i|
          iteration = i + 1
          log("--- iteration #{iteration}/#{MAX_ITERATIONS} ---")

          response   = @llm_client.chat_with_tools(messages: messages, tools: tool_definitions)
          messages  << build_assistant_message(response)

          tool_calls = Array(response['tool_calls'])
          content    = response['content'].to_s.strip

          log("content: #{content[0, 200]}") unless content.empty?
          log("tool_calls: #{tool_calls.size}") if tool_calls.any?

          if tool_calls.empty?
            log('no tool calls — agent finished without submitting')
            break
          end

          tool_calls.each do |tc|
            tool_name = tc.dig('function', 'name').to_s
            arguments = parse_arguments(tc.dig('function', 'arguments'))
            log("tool: #{tool_name}(#{arguments.to_json})")

            result = @tool_executor.call(name: tool_name, arguments: arguments)
            log("result: #{JSON.generate(result)[0, 400]}")

            messages << {
              role: 'tool',
              tool_call_id: tc['id'],
              content: JSON.generate(result)
            }

            final_result = result if tool_name == 'submit_answer' && result[:verification]
          end

          break if final_result
        end

        raise 'Firmware agent did not submit a valid answer within the iteration limit' if final_result.nil?

        final_result
      end

      private

      def build_assistant_message(response)
        msg        = { role: response.fetch('role', 'assistant') }
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
              description: 'Execute a shell command on the remote virtual machine. ' \
                           'Use `help` first to learn available commands. ' \
                           'Handles rate-limits and bans automatically (will wait and retry). ' \
                           'Returns { "output": "..." } on success.',
              parameters: {
                type: 'object',
                additionalProperties: false,
                required: ['cmd'],
                properties: {
                  cmd: {
                    type: 'string',
                    description: 'The shell command to execute, e.g. "ls /opt/firmware/cooler" or "/opt/firmware/cooler/cooler.bin"'
                  }
                }
              }
            }
          },
          {
            type: 'function',
            function: {
              name: 'submit_answer',
              description: 'Submit the ECCS- confirmation code obtained from running the cooler binary. ' \
                           'Only call this when you have the exact code from the binary output.',
              parameters: {
                type: 'object',
                additionalProperties: false,
                required: ['confirmation'],
                properties: {
                  confirmation: {
                    type: 'string',
                    description: 'The confirmation code from the cooler binary, format: ECCS- followed by hex characters'
                  }
                }
              }
            }
          }
        ]
      end

      def log(message)
        @logger.puts("[firmware] #{message}")
      end
    end
  end
end
