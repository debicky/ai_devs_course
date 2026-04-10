# frozen_string_literal: true

module Services
  module Goingthere
    class Runner
      TASK_NAME           = 'goingthere'
      MAX_COLUMNS         = 12
      MAX_ATTEMPTS        = 50
      COMMAND_DELAY       = 0.3
      COMMAND_RETRIES     = 10
      COMMAND_RETRY_DELAY = 3

      ROW_DELTA = { 'go' => 0, 'left' => -1, 'right' => 1 }.freeze

      def initialize(hub_client:, frequency_scanner:, hint_interpreter:, logger: $stdout)
        @hub               = hub_client
        @frequency_scanner = frequency_scanner
        @hint_interpreter  = hint_interpreter
        @logger            = logger
      end

      def call
        MAX_ATTEMPTS.times do |attempt|
          log "=== Attempt #{attempt + 1}/#{MAX_ATTEMPTS} ==="

          result = run_game
          return result if result[:flag]

          log 'Crashed or failed, restarting...'
          sleep 3
        rescue StandardError => e
          log "ERROR in attempt #{attempt + 1}: #{e.class}: #{e.message}"
          sleep 5
        end

        raise "Failed to complete goingthere after #{MAX_ATTEMPTS} attempts"
      end

      private

      def run_game
        start_response = send_command('start')
        log "START: #{start_response.inspect}"

        flag = extract_flag(start_response)
        return { flag: flag, attempt: 0 } if flag

        state = parse_start_state(start_response)
        current_row = state[:row]
        current_col = state[:col]
        target_row  = state[:target_row]

        log "Position: col=#{current_col}, row=#{current_row}, target=row #{target_row}, col #{MAX_COLUMNS}"

        while current_col < MAX_COLUMNS
          log "--- Column #{current_col}, Row #{current_row} ---"

          # Step 1: Check frequency scanner for OKO radar traps
          disarmed = scan_and_disarm
          unless disarmed
            log '  Disarm failed, game likely over — restarting'
            return { flag: nil }
          end

          # Step 2: Get radio hint and interpret it
          command = @hint_interpreter.interpret(current_row: current_row)

          # Step 3: Execute the move
          sleep(COMMAND_DELAY)
          response = send_command(command)
          log "  move '#{command}' → #{format_response(response)}"

          # Check for flag
          flag = extract_flag(response)
          if flag
            log "FLAG FOUND: #{flag}"
            return { flag: flag, attempt: current_col }
          end

          # Check for crash
          if crashed?(response)
            log '  CRASHED!'
            return { flag: nil }
          end

          # Update position
          current_row += ROW_DELTA.fetch(command, 0)
          current_col += 1

          log "  → col=#{current_col}, row=#{current_row}"
        end

        { flag: nil }
      end

      def scan_and_disarm
        scan_result = @frequency_scanner.scan

        if scan_result == :clear
          log '  Scanner: clear'
          return true
        end

        log "  TRAPPED! frequency=#{scan_result[:frequency]}, code=#{scan_result[:detection_code]}"
        @frequency_scanner.disarm(
          frequency: scan_result[:frequency],
          detection_code: scan_result[:detection_code]
        )
        log '  Radar disarmed.'
        true
      rescue RuntimeError => e
        log "  Disarm FAILED: #{e.message[0, 200]}"
        false
      end

      def send_command(command)
        payload = { command: command }

        COMMAND_RETRIES.times do |i|
          result = @hub.verify(task: TASK_NAME, answer: payload)
          return result
        rescue Clients::HttpError => e
          code = e.code.to_i

          # 400 = game event (crash, shot down, invalid move) — don't retry
          if code == 400
            body = e.body.to_s
            log "  command '#{command}' → HTTP 400: #{body[0, 500]}"
            parsed = safe_json_parse(body)
            return parsed || { 'message' => body, 'code' => 400 }
          end

          log "  command '#{command}' HTTP #{e.code}, retrying (#{i + 1}/#{COMMAND_RETRIES})..."
          sleep(COMMAND_RETRY_DELAY + rand(2))
        rescue Net::OpenTimeout, Net::ReadTimeout, Errno::ECONNRESET => e
          log "  command '#{command}' #{e.class}, retrying (#{i + 1}/#{COMMAND_RETRIES})..."
          sleep(COMMAND_RETRY_DELAY + rand(2))
        end

        raise "Command '#{command}' failed after #{COMMAND_RETRIES} retries"
      end

      def safe_json_parse(text)
        JSON.parse(text)
      rescue JSON::ParserError
        nil
      end

      def parse_start_state(response)
        row = response.dig('player', 'row') || response['row'] || 2
        col = response.dig('player', 'col') || response['col'] || 1
        target_row = response.dig('base', 'row') || response['target_row'] || 2

        { row: row.to_i, col: col.to_i, target_row: target_row.to_i }
      end

      def crashed?(response)
        msg = response.to_s.downcase
        msg.include?('crash') || msg.include?('destroyed') || msg.include?('game over') ||
          msg.include?('rozbij') || msg.include?('zestrzel') || msg.include?('hit a stone') ||
          msg.include?('shot down') || msg.include?('out of bounds')
      end

      def extract_flag(response)
        text = response.to_s
        match = text.match(/\{FLG:[^}]+}/)
        match ? match[0] : nil
      end

      def format_response(response)
        return response.inspect if response.is_a?(String)

        msg = response['message'].to_s
        pos = response['player'] || response['position']
        col_info = response['currentColumn']

        parts = []
        parts << "\"#{msg}\"" unless msg.empty?
        parts << "pos=#{pos.inspect}" if pos
        parts << "col_info=#{col_info.inspect}" if col_info
        parts.join(', ')
      end

      def log(message)
        @logger.puts("[goingthere] #{message}")
      end
    end
  end
end
