# frozen_string_literal: true

module Clients
  class HubClient
    BASE_URL             = 'https://hub.ag3nts.org'
    DOCS_BASE_PATH       = '/dane/doc/'
    PEOPLE_PATH          = '/data/%<api_key>s/people.csv'
    FIND_HIM_PATH        = '/data/%<api_key>s/findhim_locations.json'
    LOCATION_PATH        = '/api/location'
    ACCESS_LEVEL_PATH    = '/api/accesslevel'
    VERIFY_PATH          = '/verify'
    CATEGORIZE_CSV_PATH  = '/data/%<api_key>s/categorize.csv'
    ELECTRICITY_PNG_PATH = '/data/%<api_key>s/electricity.png'
    SOLVED_ELECTRICITY   = '/i/solved_electricity.png'

    def initialize(http_client:)
      @http_client = http_client
      @api_key     = fetch_api_key
    end

    def electricity_png_url(reset: false)
      path = format(ELECTRICITY_PNG_PATH, api_key: @api_key)
      url = "#{BASE_URL}#{path}"
      url += '?reset=1' if reset
      url
    end

    def solved_electricity_png_url
      "#{BASE_URL}#{SOLVED_ELECTRICITY}"
    end

    def fetch_electricity_png(reset: false)
      @http_client.get(electricity_png_url(reset: reset)).body
    end

    def fetch_categorize_csv
      path = format(CATEGORIZE_CSV_PATH, api_key: @api_key)
      @http_client.get("#{BASE_URL}#{path}").body
    end

    def fetch_people_csv
      path = format(PEOPLE_PATH, api_key: @api_key)
      @http_client.get("#{BASE_URL}#{path}").body
    end

    def fetch_spk_document(path:)
      @http_client.get(spk_document_url(path)).body
    end

    def spk_document_url(path)
      normalized_path = path.to_s.sub(%r{\A/+}, '')
      "#{BASE_URL}#{DOCS_BASE_PATH}#{normalized_path}"
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

    def verify_raw(task:, answer:)
      payload = { apikey: @api_key, task: task, answer: answer }
      @http_client.post_json_raw("#{BASE_URL}#{VERIFY_PATH}", payload: payload)
    end

    private

    def fetch_api_key
      value = ENV['AG3NTS_API_KEY'].to_s.strip
      raise ArgumentError, 'Missing required environment variable: AG3NTS_API_KEY' if value.empty?

      value
    end
  end
end
