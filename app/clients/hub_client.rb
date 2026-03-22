# frozen_string_literal: true

module Clients
  class HubClient
    BASE_URL             = 'https://hub.ag3nts.org'
    PEOPLE_PATH          = '/data/%<api_key>s/people.csv'
    FIND_HIM_PATH        = '/data/%<api_key>s/findhim_locations.json'
    LOCATION_PATH        = '/api/location'
    ACCESS_LEVEL_PATH    = '/api/accesslevel'
    VERIFY_PATH          = '/verify'

    def initialize(http_client:)
      @http_client = http_client
      @api_key     = fetch_api_key
    end

    def fetch_people_csv
      path = format(PEOPLE_PATH, api_key: @api_key)
      @http_client.get("#{BASE_URL}#{path}").body
    end

    def fetch_find_him_locations
      path = format(FIND_HIM_PATH, api_key: @api_key)
      response = @http_client.get("#{BASE_URL}#{path}")
      JSON.parse(response.body)
    end

    def fetch_person_locations(name:, surname:)
      payload = {
        apikey: @api_key,
        name: name,
        surname: surname
      }

      response = @http_client.post_json("#{BASE_URL}#{LOCATION_PATH}", payload: payload)
      JSON.parse(response.body)
    end

    def fetch_access_level(name:, surname:, birth_year:)
      payload = {
        apikey: @api_key,
        name: name,
        surname: surname,
        birthYear: Integer(birth_year)
      }

      response = @http_client.post_json("#{BASE_URL}#{ACCESS_LEVEL_PATH}", payload: payload)
      JSON.parse(response.body)
    end

    def verify(task:, answer:)
      payload = { apikey: @api_key, task: task, answer: answer }
      response = @http_client.post_json("#{BASE_URL}#{VERIFY_PATH}", payload: payload)
      JSON.parse(response.body)
    end

    private

    def fetch_api_key
      value = ENV['AG3NTS_API_KEY'].to_s.strip
      raise ArgumentError, 'Missing required environment variable: AG3NTS_API_KEY' if value.empty?

      value
    end
  end
end
