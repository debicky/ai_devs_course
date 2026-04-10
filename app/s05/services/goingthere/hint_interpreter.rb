# frozen_string_literal: true

module Services
  module Goingthere
    class HintInterpreter
      MAX_RETRIES = 10
      RETRY_DELAY = 3
      HINT_URL    = 'https://hub.ag3nts.org/api/getmessage'

      # LLM prompt: determine where the rock is
      SYSTEM_PROMPT = <<~PROMPT
        You help navigate a rocket on a 3-row grid (rows 1, 2, 3). Row 1 is top, row 3 is bottom.
        The rocket is at row %<row>d. Each column has exactly ONE rock.

        A radio hint describes where the rock is in the NEXT column, relative to the rocket.
        Nautical terminology:
        - "port" / "port side" = left/above the rocket = towards row 1
        - "starboard" / "starboard side" = right/below the rocket = towards row 3
        - "bow" / "nose" / "ahead" / "front" / "forward" / "dead ahead" / "cockpit" / "flight line" / "current heading" = SAME row as rocket = row %<row>d
        - "flanks" / "sides" / "wings" = both port and starboard

        CRITICAL RULES:
        1. Find where the ROCK/STONE/OBSTRUCTION is — focus on the BLOCKED direction.
        2. "sides are clear/open" + "rock ahead/front" → rock at row %<row>d
        3. "rock beside starboard" → rock BELOW rocket
        4. "rock beside port" → rock ABOVE rocket
        5. If ahead is described as SAFE/OPEN and port is SAFE/OPEN, then rock must be at starboard (below).
        6. If ahead is described as SAFE/OPEN and starboard is SAFE/OPEN, then rock must be at port (above).

        Map the rock to an absolute row number (1, 2, or 3).
        Respond with ONLY a single digit: the row number where the ROCK is.
      PROMPT

      def initialize(http_client:, llm_client:, api_key:, logger: $stdout)
        @http_client    = http_client
        @llm_client     = llm_client
        @api_key        = api_key
        @logger         = logger
        @ahead_counter  = 0 # alternates dodge direction for "ahead" rocks
      end

      # Returns "go", "left", or "right"
      def interpret(current_row:)
        hint_text = fetch_hint
        log "  radio hint: #{hint_text}"

        rock_row = determine_rock_row(hint_text, current_row)
        log "  rock at row: #{rock_row} (we are at row #{current_row})"

        command = choose_safe_command(rock_row, current_row)
        log "  command: #{command}"
        command
      end

      private

      def determine_rock_row(hint_text, current_row)
        system_content = format(SYSTEM_PROMPT, row: current_row)
        messages = [
          { role: 'system', content: system_content },
          { role: 'user', content: "Hint: \"#{hint_text}\"" }
        ]

        response = @llm_client.chat(messages: messages)
        raw = response['content'].to_s.strip

        digit = raw.match(/[123]/)
        if digit
          row = digit[0].to_i
          return row if row >= 1 && row <= 3
        end

        log "  LLM returned unexpected: #{raw}, defaulting to current row"
        current_row
      end

      # Choose command to avoid the rock row
      def choose_safe_command(rock_row, current_row)
        if rock_row == current_row
          # Rock ahead — must dodge. Alternate between left and right across attempts.
          @ahead_counter += 1
          case current_row
          when 1
            'right'
          when 3
            'left'
          else
            @ahead_counter.odd? ? 'left' : 'right'
          end
        elsif rock_row < current_row
          # Rock is above us — safe to go straight
          'go'
        else
          # Rock is below us — safe to go straight
          'go'
        end
      end

      def fetch_hint
        MAX_RETRIES.times do |i|
          response = @http_client.post_json_raw(HINT_URL, payload: { apikey: @api_key })
          code = response.code.to_i
          body = response.body.to_s

          if code == 200
            parsed = safe_json_parse(body)
            hint = parsed&.fetch('hint', nil) || parsed&.fetch('message', nil) || body
            return hint.to_s.strip
          end

          log "  hint fetch error (HTTP #{code}), retrying (#{i + 1}/#{MAX_RETRIES})..."
          sleep(RETRY_DELAY + rand(2))
        rescue Clients::HttpError => e
          log "  hint fetch HTTP error (#{e.code}), retrying (#{i + 1}/#{MAX_RETRIES})..."
          sleep(RETRY_DELAY + rand(2))
        rescue Net::OpenTimeout, Net::ReadTimeout, Errno::ECONNRESET => e
          log "  hint fetch timeout (#{e.class}), retrying (#{i + 1}/#{MAX_RETRIES})..."
          sleep(RETRY_DELAY + rand(2))
        end

        raise "Radio hint fetch failed after #{MAX_RETRIES} retries"
      end

      def safe_json_parse(text)
        JSON.parse(text)
      rescue JSON::ParserError
        nil
      end

      def log(message)
        @logger.puts("[goingthere] #{message}")
      end
    end
  end
end
