# frozen_string_literal: true

module Services
  module Timetravel
    # Fully automated runner that guides CHRONOS-P1 through three time jumps
    # by controlling both the API (/verify) and the web backend (/timetravel_backend).
    #
    # Jump plan:
    #   1. Jump to 2238-11-05 (future) — pick up batteries
    #   2. Return to 2026-04-10 (today) — come back
    #   3. Open tunnel to 2024-11-12 — meet Rafał
    class Runner
      TASK_NAME = 'timetravel'
      BACKEND_URL = 'https://hub.ag3nts.org/timetravel_backend'

      JUMPS = [
        { day: 5,  month: 11, year: 2238, direction: :future, tunnel: false,
          label: 'JUMP 1 → 2238-11-05 (pick up batteries)' },
        { day: 10, month: 4,  year: 2026, direction: :past,   tunnel: false,
          label: 'JUMP 2 → 2026-04-10 (return to present)' },
        { day: 12, month: 11, year: 2024, direction: :past,   tunnel: true,
          label: 'JUMP 3 → 2024-11-12 (open tunnel to meet Rafał)' }
      ].freeze

      # internalMode required per year range
      INTERNAL_MODE_RANGES = {
        1 => (0...2000),
        2 => (2000..2150),
        3 => (2151..2300),
        4 => (2301..2499)
      }.freeze

      POLL_INTERVAL  = 2
      MODE_TIMEOUT   = 60

      # Polish number words → values (longest-first matching avoids substring issues)
      PL_WORDS = {
        'tysiąc' => 1000, 'tysiac' => 1000,
        'dziewięćset' => 900, 'dziewiecset' => 900,
        'osiemset' => 800,
        'siedemset' => 700,
        'sześćset' => 600, 'szescset' => 600,
        'pięćset' => 500, 'piecset' => 500,
        'czterysta' => 400,
        'trzysta' => 300,
        'dwieście' => 200, 'dwiescie' => 200,
        'sto' => 100,
        'dziewięćdziesiąt' => 90, 'dziewiecdziesiat' => 90,
        'osiemdziesiąt' => 80, 'osiemdziesiat' => 80,
        'siedemdziesiąt' => 70, 'siedemdziesiat' => 70,
        'sześćdziesiąt' => 60, 'szescdziesiat' => 60,
        'pięćdziesiąt' => 50, 'piecdziesiat' => 50,
        'czterdzieści' => 40, 'czterdziesci' => 40,
        'trzydzieści' => 30, 'trzydziesci' => 30,
        'dwadzieścia' => 20, 'dwadziescia' => 20,
        'dziewiętnaście' => 19, 'dziewietnascie' => 19,
        'osiemnaście' => 18, 'osiemnascie' => 18,
        'siedemnaście' => 17, 'siedemnascie' => 17,
        'szesnaście' => 16, 'szesnascie' => 16,
        'piętnaście' => 15, 'pietnascie' => 15,
        'czternaście' => 14, 'czternascie' => 14,
        'trzynaście' => 13, 'trzynascie' => 13,
        'dwanaście' => 12, 'dwanascie' => 12,
        'jedenaście' => 11, 'jedenascie' => 11,
        'dziesięć' => 10, 'dziesiec' => 10,
        'dziewięć' => 9, 'dziewiec' => 9,
        'osiem' => 8,
        'siedem' => 7,
        'sześć' => 6, 'szesc' => 6,
        'pięć' => 5, 'piec' => 5,
        'cztery' => 4,
        'trzy' => 3,
        'dwa' => 2, 'dwie' => 2,
        'jeden' => 1, 'jedna' => 1, 'jedno' => 1,
        'zero' => 0
      }.freeze

      # Keywords indicating add/subtract
      ADD_KEYWORDS = %w[zwiększyć zwiekszic dodać dodac podnieś podnies doliczyć
                        zwiększenie podwyższenie powiększenie].freeze
      SUB_KEYWORDS = %w[obniżenie obnizenie odjąć odjac obniżyć obnizyc zmniejszyć
                        zmniejszyc odliczenie pomniejszenie].freeze

      def initialize(hub_client:, http_client:, sync_calculator:, pwr_table:, api_key:, logger: $stdout)
        @hub             = hub_client
        @http            = http_client
        @sync_calculator = sync_calculator
        @pwr_table       = pwr_table
        @api_key         = api_key
        @log             = logger
      end

      def call
        log '╔══════════════════════════════════════════════════════════════╗'
        log '║         CHRONOS-P1 Fully Automated Time Travel              ║'
        log '╚══════════════════════════════════════════════════════════════╝'
        log ''

        # Start with help
        log '─── Calling API: help ───'
        result = api_action('help')
        log_json(result)

        # Reset device
        log '─── Resetting device ───'
        result = api_action('reset')
        log_json(result)

        JUMPS.each do |jump|
          log ''
          log '═' * 64
          log "  #{jump[:label]}"
          log '═' * 64
          log ''

          result = execute_jump(jump)

          flag = extract_flag(result)
          next unless flag

          log ''
          log "🚩 FLAG FOUND: #{flag}"
          return { flag: flag }
        end

        # Final check
        log '─── Final config check ───'
        final = api_action('getConfig')
        log_json(final)

        flag = extract_flag(final)
        { flag: flag }
      end

      private

      # ── Execute a single jump ───────────────────────────────────────────

      def execute_jump(jump)
        day   = jump[:day]
        month = jump[:month]
        year  = jump[:year]

        sync_ratio  = @sync_calculator.call(day: day, month: month, year: year)
        pwr         = @pwr_table.lookup(year)
        mode_needed = required_internal_mode(year)

        pt_a = jump[:direction] == :past || jump[:tunnel]
        pt_b = jump[:direction] == :future || jump[:tunnel]

        log "  Target date : #{year}-#{format('%02d', month)}-#{format('%02d', day)}"
        log "  Sync ratio  : #{format('%.2f', sync_ratio)}"
        log "  PWR level   : #{pwr}"
        log "  internalMode: #{mode_needed}"
        log "  PT-A        : #{pt_a ? 'ON' : 'OFF'}"
        log "  PT-B        : #{pt_b ? 'ON' : 'OFF'}"
        log "  Type        : #{jump[:tunnel] ? 'TUNNEL' : 'JUMP'}"
        log ''

        # Step 1: Ensure standby mode
        log '  [1] Setting standby mode…'
        backend_update(mode: 'standby')
        sleep 1

        # Step 2: Set PT-A, PT-B, PWR via backend
        log "  [2] Setting PT-A=#{pt_a}, PT-B=#{pt_b}, PWR=#{pwr}…"
        backend_update(PTA: pt_a)
        sleep 0.5
        backend_update(PTB: pt_b)
        sleep 0.5
        backend_update(PWR: pwr)
        sleep 1

        # Step 3: Configure date via API
        log '  [3] Configuring date via API…'
        configure('year', year)
        configure('month', month)
        configure('day', day)

        # Step 4: Configure syncRatio
        log "  [4] Setting syncRatio=#{format('%.2f', sync_ratio)}…"
        configure('syncRatio', sync_ratio)

        # Step 5: Read config and parse stabilization from Polish hint
        log '  [5] Reading stabilization hint…'
        config = api_action('getConfig')
        log_json(config)

        stabilization = parse_stabilization_from_response(config)
        if stabilization
          log "  → Setting stabilization = #{stabilization}"
          configure('stabilization', stabilization)
        else
          log '  ⚠ Could not parse stabilization!'
        end

        # Step 6: Verify flux density
        log '  [6] Verifying configuration…'
        sleep 1
        config = api_action('getConfig')
        log_json(config)
        flux = extract_flux_density(config)
        log "  Flux Density: #{flux}"

        retries = 0
        while flux.to_i < 100 && retries < 3
          retries += 1
          log "  ⚠ Flux != 100% (attempt #{retries}). Re-reading hint…"
          sleep 2
          config = api_action('getConfig')
          log_json(config)

          new_stab = parse_stabilization_from_response(config)
          break unless new_stab && new_stab != stabilization

          log "  → New stabilization = #{new_stab}"
          configure('stabilization', new_stab)
          stabilization = new_stab
          sleep 1
          config = api_action('getConfig')
          flux = extract_flux_density(config)
          log "  Flux Density now: #{flux}"

        end

        # Step 7: Switch to active
        log '  [7] Switching to ACTIVE mode…'
        backend_update(mode: 'active')
        sleep 1

        # Step 8: Wait for correct internalMode
        log "  [8] Waiting for internalMode=#{mode_needed}…"
        waited = 0
        loop do
          config = poll_config
          current_mode = config['internalMode'] || config.dig('config', 'internalMode')
          log "      internalMode=#{current_mode} (need #{mode_needed}), waited #{waited}s"

          if current_mode.to_i == mode_needed
            log '      ✓ Mode matched!'
            break
          end

          if waited >= MODE_TIMEOUT
            log '      ✗ Timeout waiting for mode!'
            break
          end

          sleep POLL_INTERVAL
          waited += POLL_INTERVAL
        end

        # Step 9: Execute the jump
        log '  [9] Executing timeTravel action…'
        result = safe_api_action('timeTravel')
        log_json(result)

        flag = extract_flag(result)
        return result if flag

        sleep 2
        log '  [10] Post-jump config:'
        post = poll_config
        log_json(post)

        flag = extract_flag(post)
        return post if flag

        result
      end

      # ── Polish number parsing ───────────────────────────────────────────

      def parse_stabilization_from_response(response)
        text = response['needConfig'] || ''
        return nil if text.empty?

        log "  → needConfig: #{text}"

        # Extract all numbers (Polish words + digits) from the text
        numbers = extract_all_numbers(text)
        log "  → Extracted numbers: #{numbers.inspect}"

        return nil if numbers.size < 2

        base = numbers[0]
        adjustment = numbers[1]

        # Determine operation from context keywords
        lower_text = text.downcase
        is_add = ADD_KEYWORDS.any? { |kw| lower_text.include?(kw) }
        is_sub = SUB_KEYWORDS.any? { |kw| lower_text.include?(kw) }

        if is_add && !is_sub
          result = base + adjustment
          log "  → #{base} + #{adjustment} = #{result} (add detected)"
        elsif is_sub && !is_add
          result = base - adjustment
          log "  → #{base} - #{adjustment} = #{result} (subtract detected)"
        else
          # Ambiguous — default to subtraction
          result = (base - adjustment).abs
          log "  → #{base} - #{adjustment} = #{result} (default subtract)"
        end

        result
      end

      # Token-based number extraction — avoids Unicode word boundary issues.
      # Splits text on whitespace/punctuation, walks tokens greedily,
      # and groups consecutive Polish number words into compound values.
      def extract_all_numbers(text)
        # Normalize: strip punctuation except digits, keep spaces
        tokens = text.split(/[\s,;.!?]+/).map(&:strip).reject(&:empty?)

        numbers = []
        accumulator = 0
        in_number = false

        tokens.each do |token|
          lower = token.downcase

          pl_val = PL_WORDS[lower]
          digit_val = token.match?(/\A\d+\z/) ? token.to_i : nil

          if pl_val
            accumulator += pl_val
            in_number = true
          elsif digit_val
            # Flush any accumulated Polish number first
            if in_number && accumulator.positive?
              numbers << accumulator
              accumulator = 0
              in_number = false
            end
            numbers << digit_val
          elsif in_number && accumulator.positive?
            # Non-number token — flush accumulated Polish number
            numbers << accumulator
            accumulator = 0
            in_number = false
          end
        end

        # Flush any trailing accumulated value
        numbers << accumulator if in_number && accumulator.positive?

        numbers
      end

      # ── Backend (web UI) helper ─────────────────────────────────────────

      def backend_update(fields)
        payload = fields.merge(apikey: @api_key)
        uri = URI(BACKEND_URL)
        response = Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: 10, read_timeout: 15) do |http|
          req = Net::HTTP::Post.new(uri)
          req['Content-Type'] = 'application/json'
          req.body = JSON.generate(payload)
          http.request(req)
        end
        data = begin
          JSON.parse(response.body)
        rescue StandardError
          {}
        end
        log "      backend #{fields.reject { |k, _| k == :apikey }} → #{response.code}"
        data
      rescue StandardError => e
        log "      backend error: #{e.message}"
        {}
      end

      def poll_config
        uri = URI("#{BACKEND_URL}?apikey=#{URI.encode_www_form_component(@api_key)}")
        response = Net::HTTP.get_response(uri)
        data = begin
          JSON.parse(response.body)
        rescue StandardError
          {}
        end
        data['config'] || data
      rescue StandardError => e
        log "      poll error: #{e.message}"
        {}
      end

      # ── API helpers ─────────────────────────────────────────────────────

      def api_action(action)
        @hub.verify(task: TASK_NAME, answer: { action: action })
      end

      def safe_api_action(action)
        @hub.verify(task: TASK_NAME, answer: { action: action })
      rescue Clients::HttpError => e
        log "      API error: #{e.body}"
        begin
          JSON.parse(e.body)
        rescue StandardError
          { 'error' => e.body }
        end
      end

      def configure(param, value)
        result = @hub.verify(
          task: TASK_NAME,
          answer: { action: 'configure', param: param, value: value }
        )
        msg = result['message'] || result.to_s[0, 150]
        log "      configure #{param}=#{value} → #{msg}"
        result
      end

      # ── Extraction helpers ──────────────────────────────────────────────

      def extract_flux_density(config)
        cfg = config['config'] || config
        cfg['fluxDensity'] || cfg['flux_density'] || cfg['flux'] || 0
      end

      def extract_flag(response)
        return nil unless response.is_a?(Hash)

        text = response.to_s
        match = text.match(/\{FLG:[^}]+\}/)
        return match[0] if match

        response['flag'] || response['FLG']
      end

      def required_internal_mode(year)
        INTERNAL_MODE_RANGES.each do |mode, range|
          return mode if range.include?(year)
        end
        raise ArgumentError, "Year #{year} outside supported range (1500–2499)"
      end

      # ── I/O helpers ─────────────────────────────────────────────────────

      def log(msg)
        @log.puts(msg)
      end

      def log_json(data)
        log "      #{JSON.pretty_generate(data).gsub("\n", "\n      ")}"
      rescue StandardError
        log "      #{data}"
      end
    end
  end
end
