# frozen_string_literal: true

module Clients
  class HttpClient
    DEFAULT_OPEN_TIMEOUT = 10
    DEFAULT_READ_TIMEOUT = 60
    JSON_CONTENT_TYPE    = 'application/json'

    def initialize(open_timeout: DEFAULT_OPEN_TIMEOUT, read_timeout: DEFAULT_READ_TIMEOUT)
      @open_timeout = open_timeout
      @read_timeout = read_timeout
    end

    def get(url, headers: {})
      request(url, Net::HTTP::Get, headers: headers)
    end

    def post_json(url, payload:, headers: {})
      req_headers = headers.merge('Content-Type' => JSON_CONTENT_TYPE)
      request(url, Net::HTTP::Post, headers: req_headers, body: JSON.generate(payload))
    end

    private

    def request(url, request_class, headers:, body: nil)
      uri  = URI(url)
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl      = uri.scheme == 'https'
      http.open_timeout = @open_timeout
      http.read_timeout = @read_timeout

      req = request_class.new(uri)
      headers.each { |k, v| req[k] = v }
      req.body = body if body

      response = http.request(req)
      return response if response.is_a?(Net::HTTPSuccess)

      raise StandardError, "HTTP #{response.code} #{response.message} for #{url}. Body: #{response.body}"
    end
  end
end
