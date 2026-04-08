# frozen_string_literal: true

module Services
  module Savethem
    # Thin wrapper around the hub's tool-search and dynamic tool endpoints.
    class ToolClient
      BASE_URL       = 'https://hub.ag3nts.org'
      TOOL_SEARCH    = '/api/toolsearch'

      def initialize(http_client:, api_key:, logger: $stdout)
        @http_client = http_client
        @api_key     = api_key
        @logger      = logger
      end

      # Returns array of tool descriptors: [{name:, url:, description:}, ...]
      def search(query:)
        payload  = { apikey: @api_key, query: query }
        response = @http_client.post_json("#{BASE_URL}#{TOOL_SEARCH}", payload: payload)
        parsed   = JSON.parse(response.body)
        tools    = Array(parsed['tools'])
        log("toolsearch(#{query.inspect}) → #{tools.map { |t| t['name'] }.join(', ')}")
        tools
      end

      # Call any discovered tool (they all accept {apikey:, query:} → JSON)
      def call(path:, query:)
        payload  = { apikey: @api_key, query: query }
        response = @http_client.post_json("#{BASE_URL}#{path}", payload: payload)
        parsed   = JSON.parse(response.body)
        log("tool #{path}(#{query.inspect}) → code=#{parsed['code']}")
        parsed
      end

      private

      def log(msg)
        @logger.puts("[savethem/tool] #{msg}")
      end
    end
  end
end
