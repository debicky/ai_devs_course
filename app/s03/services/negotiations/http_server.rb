# frozen_string_literal: true

require 'stringio'
require 'webrick'

module Services
  module Negotiations
    class HttpServer
      DEFAULT_PORT = 3001
      JSON_CONTENT_TYPE = 'application/json'

      def initialize(search_tool:, port: DEFAULT_PORT, logger: $stdout)
        @search_tool = search_tool
        @port        = Integer(port)
        @logger      = logger
      end

      def start
        server.start
      end

      def shutdown
        @server&.shutdown
      end

      private

      def server
        @server ||= WEBrick::HTTPServer.new(
          Port: @port,
          AccessLog: [],
          Logger: WEBrick::Log.new(StringIO.new)
        ).tap do |http_server|
          trap_signals(http_server)
          http_server.mount_proc('/healthz') { |_req, res| render_json(res, 200, { status: 'ok' }) }
          http_server.mount_proc('/api/negotiations/catalog') { |req, res| handle_search(req, res) }
        end
      end

      def handle_search(request, response)
        log("request method=#{request.request_method} path=#{request.path}")
        return render_json(response, 405, { output: 'Only POST is supported.' }) unless request.request_method == 'POST'

        payload = JSON.parse(request.body.to_s)
        params  = payload.fetch('params').to_s
        output  = @search_tool.call(params: params)
        render_json(response, 200, { output: output })
      rescue JSON::ParserError => e
        render_json(response, 400, { output: "Malformed JSON: #{e.message}" })
      rescue KeyError
        render_json(response, 400, { output: 'Missing params field.' })
      rescue StandardError => e
        render_json(response, 500, { output: "Server error: #{e.message}" })
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
        @logger.puts("[negotiations/http] #{message}")
      end
    end
  end
end
