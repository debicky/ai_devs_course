# frozen_string_literal: true

module Services
  module Negotiations
    class Runner
      TASK_NAME     = 'negotiations'
      DEFAULT_PORT  = 3001
      MAX_POLLS     = 12
      INITIAL_DELAY = 10
      POLL_DELAY    = 10
      FLAG_REGEX    = /\{FLG:[^}]+}/.freeze

      TOOL_DESCRIPTION = <<~TEXT.gsub(/\s+/, ' ').strip
        Szuka miast sprzedajacych wskazane przedmioty. Do params podaj jedno naturalne zapytanie albo kilka pozycji rozdzielonych przecinkami lub nowymi liniami. Zwraca dopasowane pozycje z katalogu i miasta wspolne dla wszystkich znalezionych pozycji.
      TEXT

      def initialize(hub_client:, search_tool:, port: DEFAULT_PORT, public_base_url: ENV['PUBLIC_BASE_URL'],
                     logger: $stdout)
        @hub_client       = hub_client
        @search_tool      = search_tool
        @port             = Integer(port)
        @public_base_url  = public_base_url.to_s.strip
        @logger           = logger
        @http_server      = HttpServer.new(search_tool: search_tool, port: @port, logger: logger)
        @server_thread    = nil
        @ngrok_pid        = nil
      end

      def call
        start_server
        public_url = resolve_public_base_url
        tool_url   = "#{public_url}/api/negotiations/catalog"
        log("tool URL: #{tool_url}")

        submission = @hub_client.verify(
          task: TASK_NAME,
          answer: {
            tools: [
              {
                URL: tool_url,
                description: TOOL_DESCRIPTION
              }
            ]
          }
        )
        log("registration response: #{submission.inspect}")

        sleep(INITIAL_DELAY)

        verification = poll_for_result
        flag = extract_flag(verification)
        raise "Negotiations verification finished without a flag: #{verification.inspect}" if flag.nil?

        { tool_url: tool_url, registration: submission, verification: verification, flag: flag }
      ensure
        stop_ngrok
        stop_server
      end

      private

      def start_server
        return if @server_thread&.alive?

        @server_thread = Thread.new { @http_server.start }
        wait_for_local_health
      end

      def wait_for_local_health
        health_url = URI("http://127.0.0.1:#{@port}/healthz")
        30.times do
          begin
            response = Net::HTTP.get_response(health_url)
            return if response.code == '200'
          rescue StandardError
            # keep waiting
          end
          sleep(0.5)
        end
        raise 'Negotiations HTTP server did not become healthy in time'
      end

      def resolve_public_base_url
        return @public_base_url unless @public_base_url.empty?

        start_ngrok
        30.times do
          url = fetch_ngrok_url
          return url if url

          sleep(1)
        end
        raise 'Could not determine ngrok public URL'
      end

      def start_ngrok
        return if @ngrok_pid

        log("starting ngrok on port #{@port}...")
        log_path = File.expand_path('../../../../tmp/ngrok.log', String(__dir__))
        FileUtils.mkdir_p(File.dirname(log_path))
        out = File.open(log_path, 'a')
        @ngrok_pid = Process.spawn('ngrok', 'http', @port.to_s, out: out, err: out)
      rescue StandardError => e
        raise "Failed to start ngrok: #{e.message}"
      end

      def fetch_ngrok_url
        uri = URI('http://127.0.0.1:4040/api/tunnels')
        response = Net::HTTP.get_response(uri)
        return nil unless response.code == '200'

        body = JSON.parse(response.body)
        tunnel = Array(body['tunnels']).find { |t| t['public_url'].to_s.start_with?('https://') }
        tunnel&.fetch('public_url', nil)
      rescue StandardError
        nil
      end

      def poll_for_result
        last = nil
        MAX_POLLS.times do |i|
          sleep(POLL_DELAY) unless i.zero?
          last = @hub_client.verify(task: TASK_NAME, answer: { action: 'check' })
          log("check #{i + 1}/#{MAX_POLLS}: #{last.inspect}")
          return last if extract_flag(last)
        end
        last
      end

      def extract_flag(payload)
        payload.to_s[FLAG_REGEX]
      end

      def stop_server
        @http_server.shutdown
        @server_thread&.join(1)
      rescue StandardError
        nil
      ensure
        @server_thread = nil
      end

      def stop_ngrok
        pid = @ngrok_pid
        return unless pid

        Process.kill('TERM', pid)
        Process.wait(pid)
      rescue StandardError
        nil
      ensure
        @ngrok_pid = nil
      end

      def log(message)
        @logger.puts("[negotiations] #{message}")
      end
    end
  end
end
