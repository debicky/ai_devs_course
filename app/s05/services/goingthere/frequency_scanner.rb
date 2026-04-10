# frozen_string_literal: true

require 'digest/sha1'

module Services
  module Goingthere
    class FrequencyScanner
      CLEAR_PATTERN    = /cl+e+a+r/i.freeze
      MAX_RETRIES      = 10
      RETRY_DELAY      = 3
      SCANNER_GET_URL  = 'https://hub.ag3nts.org/api/frequencyScanner'
      SCANNER_POST_URL = 'https://hub.ag3nts.org/api/frequencyScanner'

      def initialize(http_client:, api_key:, logger: $stdout)
        @http_client = http_client
        @api_key     = api_key
        @logger      = logger
      end

      # Returns :clear or { frequency:, detection_code: }
      def scan
        MAX_RETRIES.times do |attempt|
          body = fetch_scanner_response
          next if body.nil? # server error, retry

          log "  scanner raw: #{body[0, 300]}"

          return :clear if CLEAR_PATTERN.match?(body)

          parsed = parse_garbled_json(body)
          if parsed
            log "  scanner detected trap: frequency=#{parsed[:frequency]}, code=#{parsed[:detection_code]}"
            return parsed
          end

          log "  scanner: unparseable non-clear response (attempt #{attempt + 1}/#{MAX_RETRIES}), refetching..."
          sleep(1)
        end

        log '  scanner: all attempts exhausted, assuming clear'
        :clear
      end

      def disarm(frequency:, detection_code:)
        disarm_hash = Digest::SHA1.hexdigest("#{detection_code}disarm")
        log "  disarming: frequency=#{frequency}, hash=#{disarm_hash}"

        payload = {
          apikey: @api_key,
          frequency: frequency,
          disarmHash: disarm_hash
        }

        retries = 0
        loop do
          response = @http_client.post_json_raw(SCANNER_POST_URL, payload: payload)
          code = response.code.to_i
          body = response.body.to_s

          if code == 200
            log "  disarm OK: #{body[0, 200]}"
            return true
          end

          retries += 1
          if retries >= MAX_RETRIES
            raise "Disarm failed after #{MAX_RETRIES} retries. Last: HTTP #{code} — #{body[0, 300]}"
          end

          log "  disarm failed (HTTP #{code}), retrying (#{retries}/#{MAX_RETRIES})..."
          sleep(RETRY_DELAY)
        end
      end

      private

      def fetch_scanner_response
        url = "#{SCANNER_GET_URL}?key=#{@api_key}"

        MAX_RETRIES.times do |i|
          response = @http_client.get(url)
          return response.body.to_s
        rescue Clients::HttpError => e
          log "  scanner GET error (HTTP #{e.code}), retrying (#{i + 1}/#{MAX_RETRIES})..."
          sleep(RETRY_DELAY + rand(2))
        rescue Net::OpenTimeout, Net::ReadTimeout, Errno::ECONNRESET => e
          log "  scanner GET timeout (#{e.class}), retrying (#{i + 1}/#{MAX_RETRIES})..."
          sleep(RETRY_DELAY + rand(2))
        end

        log '  scanner: all GET retries exhausted'
        nil
      end

      # The scanner response may be garbled JSON. Try multiple extraction strategies.
      def parse_garbled_json(body)
        # Strategy 1: direct JSON parse with known keys
        parsed = safe_json_parse(body)
        if parsed
          freq = extract_frequency_from_hash(parsed)
          code = extract_detection_code_from_hash(parsed)
          return { frequency: freq, detection_code: code } if freq && code
        end

        # Strategy 2: regex extraction — keys are garbled (frepuency, betecti0nC0be)
        # Look for a standalone number (the frequency) and a short alphanumeric code
        freq = extract_frequency_from_text(body)
        code = extract_detection_code_from_text(body)

        if freq && code
          log "  parsed garbled: frequency=#{freq}, code=#{code}"
          return { frequency: freq, detection_code: code }
        end

        nil
      end

      def safe_json_parse(text)
        start_idx = text.index('{')
        return nil unless start_idx

        end_idx = text.rindex('}')
        return nil unless end_idx && end_idx > start_idx

        JSON.parse(text[start_idx..end_idx])
      rescue JSON::ParserError
        nil
      end

      # Try known and garbled key names for frequency
      def extract_frequency_from_hash(hash)
        # Direct key
        val = hash['frequency']
        return val.to_i if val.is_a?(Numeric)

        # Search all keys for frequency-like key
        hash.each do |key, val|
          next unless val.is_a?(Numeric) && val.positive? && val < 10_000

          return val.to_i if key.downcase.gsub(/[^a-z]/, '').match?(/fr.?[eqp]u.?n/i)
        end

        # Check nested hashes
        hash.each_value do |val|
          next unless val.is_a?(Hash)

          result = extract_frequency_from_hash(val)
          return result if result
        end

        nil
      end

      # Try known and garbled key names for detectionCode
      def extract_detection_code_from_hash(hash)
        val = hash['detectionCode']
        return val.to_s.strip if val && !val.to_s.strip.empty?

        # Check nested hashes first (detectionCode is usually nested under data)
        hash.each_value do |v|
          next unless v.is_a?(Hash)

          result = extract_detection_code_from_hash(v)
          return result if result
        end

        # Search all keys for detection-code-like key
        hash.each do |key, val|
          next if val.is_a?(Hash) || val.is_a?(Array)
          next if val.is_a?(TrueClass) || val.is_a?(FalseClass) || val.is_a?(Numeric)

          str = val.to_s.strip
          next if str.empty? || str.length > 50

          # Skip known non-code values
          next if str.downcase.include?('missile') || str.downcase.include?('guided')

          return str if key.downcase.gsub(/[^a-z]/, '').match?(/[db].?[te].?ct/i)
        end

        nil
      end

      # Regex fallback: find a 2-4 digit number that looks like frequency
      def extract_frequency_from_text(body)
        # Look for number after a frequency-like key
        match = body.match(/"[^"]*?[fF][rR][eE3]?[pPqQ][uU]?[eE]?[nN]?[cC]?[yY]?"?\s*[:=]\s*(\d{1,5})/m)
        return match[1].to_i if match

        # Fallback: any standalone 2-4 digit number (likely the frequency)
        numbers = body.scan(/:\s*(\d{2,4})\s*[,\n}]/).flatten.map(&:to_i)
        numbers.find { |n| n > 10 && n < 10_000 }
      end

      # Regex fallback: find the detection code (short alphanumeric string in a nested section)
      def extract_detection_code_from_text(body)
        # Strategy: find the VALUE after a detection-code-like key
        # The key is heavily garbled: betecti0nC0be, BEtECti0NC0be, beTeCtI0nc0Be, etc.
        # Common pattern: contains "tect" or "t0ct" or "teCt" somewhere
        # Look for: garbled_key <separator> <quote> VALUE <quote>
        match = body.match(/[bBdD][^\n:=]{4,20}[cC][0oO][dDbB][eE]["'`]?\s*[:=]\s*["'`]([A-Za-z0-9]{3,20})["'`]/m)
        return match[1] if match

        # Broader: any key containing 'ect' followed by a short alphanumeric value
        match = body.match(/[eE][cC][tT][^:=]{0,15}[:=]\s*["'`]([A-Za-z0-9]{3,20})["'`]/m)
        return match[1] if match

        # Fallback: find ALL short alphanumeric string values, exclude known non-codes
        candidates = body.scan(/["'`]([A-Za-z0-9]{3,20})["'`]/).flatten
        candidates.reject! do |c|
          lc = c.downcase
          lc.match?(/true|false|self|guided|missile|weapon|type|pursuit|surface|air|being|track|frequency|data/)
        end
        # Detection code is usually the last short string in the nested data block
        candidates.last
      end

      def log(message)
        @logger.puts("[goingthere] #{message}")
      end
    end
  end
end
