# frozen_string_literal: true

module Clients
  class HubClient
    BASE_URL = 'https://hub.ag3nts.org'
    VERIFY_PATH = '/verify'

    def initialize(http_client:)
      @http_client = http_client
      @api_key     = fetch_api_key
    end

    # ── Generic helpers (available to all tasks) ───────────────────────────

    def get(path)
      @http_client.get("#{BASE_URL}#{path}")
    end

    def get_body(path)
      get(path).body
    end

    def post(path, payload)
      @http_client.post_json("#{BASE_URL}#{path}", payload: payload)
    end

    def post_raw(path, payload)
      @http_client.post_json_raw("#{BASE_URL}#{path}", payload: payload)
    end

    def data_url(subpath)
      "#{BASE_URL}/data/#{@api_key}/#{subpath}"
    end

    def fetch_data(subpath)
      @http_client.get(data_url(subpath)).body
    end

    attr_reader :api_key

    # ── Verify (shared by every task) ──────────────────────────────────────

    def verify(task:, answer:)
      payload = { apikey: @api_key, task: task, answer: answer }
      response = post(VERIFY_PATH, payload)
      JSON.parse(response.body)
    end

    def verify_raw(task:, answer:)
      payload = { apikey: @api_key, task: task, answer: answer }
      post_raw(VERIFY_PATH, payload)
    end

    private

    def fetch_api_key
      value = ENV['AG3NTS_API_KEY'].to_s.strip
      raise ArgumentError, 'Missing required environment variable: AG3NTS_API_KEY' if value.empty?

      value
    end
  end
end
