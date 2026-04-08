# frozen_string_literal: true

module Clients
  class PackagesClient
    BASE_URL        = 'https://hub.ag3nts.org/api/packages'
    ACTION_CHECK    = 'check'
    ACTION_REDIRECT = 'redirect'

    def initialize(http_client:, logger: $stdout)
      @http_client = http_client
      @api_key     = fetch_api_key
      @logger      = logger
    end

    def check_package(package_id:)
      payload = {
        apikey: @api_key,
        action: ACTION_CHECK,
        packageid: package_id.to_s.strip
      }

      log_request(ACTION_CHECK, payload)
      response = @http_client.post_json(BASE_URL, payload: payload)
      log_response(ACTION_CHECK, response.body)
      JSON.parse(response.body)
    rescue Clients::HttpError => e
      log_response(ACTION_CHECK, e.body, error: true)
      raise
    end

    def redirect_package(package_id:, requested_destination:, actual_destination:, code:)
      payload = {
        apikey: @api_key,
        action: ACTION_REDIRECT,
        packageid: package_id.to_s.strip,
        destination: actual_destination.to_s.strip,
        code: code.to_s
      }

      log_redirect_request(
        package_id: package_id,
        requested_destination: requested_destination,
        actual_destination: actual_destination,
        code: code,
        payload: payload
      )
      response = @http_client.post_json(BASE_URL, payload: payload)
      log_response(ACTION_REDIRECT, response.body)
      JSON.parse(response.body)
    rescue Clients::HttpError => e
      log_response(ACTION_REDIRECT, e.body, error: true)
      raise
    end

    private

    def log_request(action, payload)
      @logger.puts("[packages] action=#{action} request=#{redacted_payload(payload).inspect}")
    end

    def log_redirect_request(package_id:, requested_destination:, actual_destination:, code:, payload:)
      @logger.puts(
        "[packages] action=#{ACTION_REDIRECT} request=#{redacted_payload(payload).inspect} " \
        "requested_destination=#{requested_destination.inspect} actual_destination=#{actual_destination.inspect} " \
        "code=#{masked_code(code)} packageid=#{package_id.inspect}"
      )
    end

    def log_response(action, body, error: false)
      suffix = error ? ' error_response' : ' response'
      @logger.puts("[packages] action=#{action}#{suffix}=#{body}")
    end

    def redacted_payload(payload)
      payload.merge(
        apikey: redact_api_key(payload[:apikey]),
        code: masked_code(payload[:code])
      )
    end

    def redact_api_key(value)
      raw = value.to_s
      return '[FILTERED]' if raw.empty?

      visible = raw[-4, 4] || raw
      "[FILTERED:...#{visible}]"
    end

    def masked_code(value)
      raw = value.to_s
      return '[EMPTY]' if raw.empty?

      "[PRESENT:length=#{raw.length}]"
    end

    def fetch_api_key
      value = ENV['AG3NTS_API_KEY'].to_s.strip
      raise ArgumentError, 'Missing required environment variable: AG3NTS_API_KEY' if value.empty?

      value
    end
  end
end
