# frozen_string_literal: true

module Clients
  class HubClient
    BASE_URL      = 'https://hub.ag3nts.org'
    PEOPLE_PATH   = '/data/%<api_key>s/people.csv'
    VERIFY_PATH   = '/verify'

    def initialize(http_client:, api_key:)
      @http_client = http_client
      @api_key     = api_key
    end

    def fetch_people_csv
      path = format(PEOPLE_PATH, api_key: @api_key)
      @http_client.get("#{BASE_URL}#{path}").body
    end

    def verify(task:, answer:)
      payload = { apikey: @api_key, task: task, answer: answer }
      response = @http_client.post_json("#{BASE_URL}#{VERIFY_PATH}", payload: payload)
      JSON.parse(response.body)
    end
  end
end
