# frozen_string_literal: true

module Services
  module Shellaccess
    class ToolExecutor
      TOOL_NAMES       = %w[execute_shell].freeze
      TASK_NAME        = 'shellaccess'
      DEFAULT_BAN_WAIT = 30
      MAX_BAN_WAIT     = 120
      MAX_RETRIES      = 5
      RETRY_WAIT       = 5

      def initialize(hub_client:, logger: $stdout)
        @hub_client = hub_client
        @logger     = logger
      end

      def call(name:, arguments:)
        raise ArgumentError, "Unknown tool: #{name}" unless TOOL_NAMES.include?(name)

        execute_shell(arguments)
      end

      private

      def execute_shell(arguments)
        cmd = arguments.fetch('cmd', '').to_s.strip
        return { error: 'cmd is required' } if cmd.empty?

        log("$ #{cmd}")

        retries = 0
        loop do
          resp = @hub_client.verify_raw(task: TASK_NAME, answer: { cmd: cmd })
          code = resp.code.to_i
          body = resp.body.to_s

          case code
          when 200
            log("  → #{body[0, 500]}")
            return { output: body }
          when 429
            wait = extract_wait_seconds(body) || DEFAULT_BAN_WAIT
            wait = [wait, MAX_BAN_WAIT].min
            log("  RATE-LIMITED (#{body.strip[0, 120]}) — waiting #{wait}s...")
            sleep(wait)
            retries += 1
          when 503
            log("  503 Service Unavailable — waiting #{RETRY_WAIT}s (attempt #{retries + 1})...")
            sleep(RETRY_WAIT)
            retries += 1
          else
            log("  HTTP #{code}: #{body[0, 500]}")
            return { output: "HTTP #{code}: #{body}" }
          end

          return { error: "Shell API unavailable after #{retries} retries" } if retries >= MAX_RETRIES
        end
      rescue KeyError
        { error: 'cmd argument is required' }
      rescue StandardError => e
        { error: "execute_shell error: #{e.message}" }
      end

      def extract_wait_seconds(body)
        match = body.to_s.match(/(\d+)\s*s(?:ec(?:ond)?s?)?/i)
        match ? match[1].to_i : nil
      end

      def log(msg)
        @logger.puts("[shellaccess] #{msg}")
      end
    end
  end
end

