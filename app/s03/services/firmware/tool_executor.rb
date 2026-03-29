# frozen_string_literal: true

module Services
  module Firmware
    class ToolExecutor
      TOOL_NAMES = %w[execute_shell submit_answer].freeze

      # Seconds to sleep when a ban is detected (override via env BAN_WAIT_SECONDS)
      DEFAULT_BAN_WAIT = 30
      MAX_BAN_WAIT     = 120
      RETRY_WAIT       = 5

      def initialize(hub_client:, logger: $stdout)
        @hub_client = hub_client
        @logger     = logger
      end

      def call(name:, arguments:)
        raise ArgumentError, "Unknown tool: #{name}" unless TOOL_NAMES.include?(name)

        public_send(name, arguments)
      end

      def execute_shell(arguments)
        cmd = arguments.fetch('cmd', '').to_s.strip
        return { error: 'cmd is required' } if cmd.empty?

        log("$ #{cmd}")

        retries = 0
        loop do
          result = @hub_client.shell_cmd(cmd: cmd)
          code   = result[:code]
          body   = result[:body]

          case code
          when 200
            log("  → #{body[0, 200]}")
            return { output: body }
          when 429
            wait = extract_wait_seconds(body) || DEFAULT_BAN_WAIT
            wait = [wait, MAX_BAN_WAIT].min
            log("  RATE-LIMITED/BANNED (#{body.strip[0, 120]}) — waiting #{wait}s...")
            sleep(wait)
            retries += 1
          when 503
            log("  503 Service Unavailable — waiting #{RETRY_WAIT}s (attempt #{retries + 1})...")
            sleep(RETRY_WAIT)
            retries += 1
          else
            log("  HTTP #{code}: #{body[0, 200]}")
            return { output: "HTTP #{code}: #{body}" }
          end

          return { error: "Shell API unavailable after #{retries} retries" } if retries >= 5
        end
      rescue KeyError
        { error: 'cmd argument is required' }
      rescue StandardError => e
        { error: "execute_shell error: #{e.message}" }
      end

      def submit_answer(arguments)
        confirmation = arguments.fetch('confirmation', '').to_s.strip
        return { error: 'confirmation code is required' } if confirmation.empty?

        log("Submitting confirmation: #{confirmation}")
        body = @hub_client.verify(task: 'firmware', answer: { confirmation: confirmation })
        { verification: body, confirmation: confirmation }
      rescue StandardError => e
        { error: "submit error: #{e.message}" }
      end

      private

      def extract_wait_seconds(body)
        # Parses messages like "banned for 30 seconds" or "try again in 45s"
        match = body.to_s.match(/(\d+)\s*s(?:ec(?:ond)?s?)?/i)
        match ? match[1].to_i : nil
      end

      def log(msg)
        @logger.puts("[firmware/shell] #{msg}")
      end
    end
  end
end
