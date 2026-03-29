# frozen_string_literal: true

module Services
  module Railway
    class Runner
      TASK_NAME = 'railway'
      TARGET_ROUTE = 'X-01'
      OPEN_STATUS = 'open'
      CLOSED_STATUS = 'close'
      RECONFIGURE_MODE = 'reconfigure'
      NORMAL_MODE = 'normal'
      OPEN_VALUE = 'RTOPEN'
      EXPECTED_ACTIONS = %w[help reconfigure getstatus setstatus save].freeze
      DEFAULT_REQUEST_INTERVAL = 31
      MAX_503_RETRIES = 6
      BASE_BACKOFF_SECONDS = 2
      MAX_BACKOFF_SECONDS = 60

      def initialize(hub_client:, logger: $stdout, route: TARGET_ROUTE)
        @hub_client = hub_client
        @logger = logger
        @route = route
        @next_request_at = nil
      end

      def call
        help_response = request_json!(action: 'help')
        validate_help!(help_response)

        status_response = request_json!(action: 'getstatus', route: @route)
        final_response = follow_sequence(status_response)
        flag = extract_flag(final_response)

        raise ArgumentError, 'Railway flow finished without a flag in the response' unless flag

        {
          route: @route,
          flag: flag,
          verification: final_response
        }
      end

      private

      def follow_sequence(status_response)
        response = status_response

        response = request_json!(action: 'reconfigure', route: @route) if response['mode'] == NORMAL_MODE

        if response['mode'] == RECONFIGURE_MODE && response['status'] == CLOSED_STATUS
          response = request_json!(action: 'setstatus', route: @route, value: OPEN_VALUE)
        end

        if response['mode'] == RECONFIGURE_MODE
          response = request_json!(action: 'save', route: @route)
          return response if extract_flag(response)
        end

        final_status = request_json!(action: 'getstatus', route: @route)
        return final_status if extract_flag(final_status)

        raise ArgumentError,
              "Route #{@route} processed but no flag was returned. Final response: #{final_status.inspect}"
      end

      def validate_help!(response)
        actions = Array(response.dig('help', 'actions')).map { |entry| entry['action'] }
        missing = EXPECTED_ACTIONS - actions
        return if missing.empty?

        raise ArgumentError, "Railway help response is missing actions: #{missing.join(', ')}"
      end

      def request_json!(answer)
        service_unavailable_attempts = 0

        loop do
          wait_if_needed
          log_request(answer)
          response = @hub_client.verify_raw(task: TASK_NAME, answer: answer)
          body = parse_body(response.body)
          log_response(response, body)

          case response.code
          when '200'
            schedule_next_request(response)
            return body
          when '429'
            delay = retry_delay_seconds(response, body)
            log("rate limit hit; sleeping #{delay}s")
            sleep(delay)
          when '503'
            service_unavailable_attempts += 1
            if service_unavailable_attempts > MAX_503_RETRIES
              raise ArgumentError, "Railway API kept returning 503 after #{MAX_503_RETRIES} retries"
            end

            delay = backoff_delay_seconds(service_unavailable_attempts, response, body)
            log("service unavailable; retry #{service_unavailable_attempts}/#{MAX_503_RETRIES} in #{delay}s")
            sleep(delay)
          else
            message = body.is_a?(Hash) ? body['message'] || body['error'] : body.to_s
            raise ArgumentError, "Railway API returned HTTP #{response.code}: #{message}"
          end
        end
      end

      def wait_if_needed
        return unless @next_request_at

        remaining = (@next_request_at - Time.now).ceil
        return unless remaining.positive?

        log("cooldown active; sleeping #{remaining}s")
        sleep(remaining)
      end

      def schedule_next_request(response)
        @next_request_at = Time.now + default_interval_seconds(response)
      end

      def default_interval_seconds(response)
        policy_window = parse_rate_limit_window(response['x-ratelimit-policy'])
        return policy_window + 1 if policy_window

        DEFAULT_REQUEST_INTERVAL
      end

      def parse_rate_limit_window(policy)
        return nil if policy.to_s.strip.empty?

        match = policy.to_s.match(/w=(\d+)/)
        match ? match[1].to_i : nil
      end

      def retry_delay_seconds(response, body)
        retry_after = response['retry-after'].to_s.strip
        return retry_after.to_i if retry_after.match?(/\A\d+\z/) && retry_after.to_i.positive?

        body_retry_after = body.is_a?(Hash) ? body['retry_after'] : nil
        return body_retry_after.to_i if body_retry_after.to_i.positive?

        reset_time = response['x-ratelimit-reset'].to_s.strip
        if reset_time.match?(/\A\d+\z/)
          delay = reset_time.to_i - Time.now.to_i
          return delay + 1 if delay.positive?
        end

        default_interval_seconds(response)
      end

      def backoff_delay_seconds(attempt, response, body)
        retry_after = retry_delay_seconds(response, body)
        exponential = [BASE_BACKOFF_SECONDS * (2**(attempt - 1)), MAX_BACKOFF_SECONDS].min
        [retry_after, exponential].max
      end

      def parse_body(body)
        JSON.parse(body)
      rescue JSON::ParserError
        { 'raw' => body.to_s }
      end

      def extract_flag(response)
        message = response.is_a?(Hash) ? response['message'].to_s : response.to_s
        match = message.match(/\{FLG:[^}]+}/)
        match && match[0]
      end

      def log_request(answer)
        log("request body=#{JSON.generate(answer)}")
      end

      def log_response(response, body)
        log("response status=#{response.code} #{response.message}")
        headers = response.each_header.to_h
        log("response headers=#{headers.inspect}")
        formatted_body = body.is_a?(Hash) || body.is_a?(Array) ? JSON.pretty_generate(body) : body.to_s
        log("response body=#{formatted_body}")
      end

      def log(message)
        @logger.puts("[railway] #{message}")
      end
    end
  end
end
