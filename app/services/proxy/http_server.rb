# frozen_string_literal: true

require 'stringio'
require 'webrick'

module Services
  module Proxy
    class HttpServer
      DEFAULT_PORT = 3000
      JSON_CONTENT_TYPE = 'application/json'

      def initialize(conversation_runner:, port: DEFAULT_PORT, logger: $stdout)
        @conversation_runner = conversation_runner
        @port = Integer(port)
        @logger = logger
      end

      def start
        server.start
      end

      private

      def server
        @server ||= WEBrick::HTTPServer.new(
          Port: @port,
          AccessLog: [],
          Logger: WEBrick::Log.new(StringIO.new)
        ).tap do |http_server|
          trap_signals(http_server)
          http_server.mount_proc('/') { |request, response| handle(request, response) }
        end
      end

      def handle(request, response)
        log("request method=#{request.request_method} path=#{request.path}")

        return render_json(response, 405, { error: 'Only POST is supported' }) unless request.request_method == 'POST'

        payload = parse_json(request.body)
        session_id = fetch_string(payload, 'sessionID')
        msg = fetch_string(payload, 'msg')
        result = @conversation_runner.call(session_id: session_id, user_message: msg)
        render_json(response, 200, result)
      rescue JSON::ParserError => e
        render_json(response, 400, { error: "Malformed JSON: #{e.message}" })
      rescue KeyError => e
        render_json(response, 400, { error: "Missing field: #{e.message}" })
      rescue ArgumentError => e
        render_json(response, 400, { error: e.message })
      rescue Clients::HttpError => e
        render_json(response, 502, { error: e.message })
      rescue StandardError => e
        render_json(response, 500, { error: e.message })
      end

      def parse_json(body)
        JSON.parse(body.to_s)
      end

      def fetch_string(payload, key)
        value = payload.fetch(key).to_s.strip
        raise ArgumentError, "#{key} must be a non-empty string" if value.empty?

        value
      end

      def render_json(response, status, body)
        response.status = status
        response['Content-Type'] = JSON_CONTENT_TYPE
        response.body = JSON.generate(body)
      end

      def trap_signals(http_server)
        %w[INT TERM].each do |signal|
          Signal.trap(signal) { http_server.shutdown }
        end
      end

      def log(message)
        @logger.puts("[proxy] #{message}")
      end
    end
  end
end
