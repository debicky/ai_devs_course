# frozen_string_literal: true

module Services
  module Windpower
    class Runner
      TASK_NAME = 'windpower'
      CUTOFF_WIND_MS = 14   # above this → storm, protect blades
      MIN_WIND_MS    = 4    # below this → no generation
      RATED_POWER_KW = 14

      def initialize(hub_client:, logger: $stdout)
        @hub = hub_client
        @log = logger
      end

      def call
        # ── 1. Start service window (40s timer begins) ────────────────────
        log 'Starting windpower session...'
        start = api(action: 'start')
        log "Session started: #{start['sessionStart']} (#{start['sessionTimeout']}s timeout)"

        # ── 2. Queue data requests in parallel ────────────────────────────
        threads = [
          Thread.new { api(action: 'get', param: 'weather') },
          Thread.new { api(action: 'get', param: 'powerplantcheck') }
        ]
        threads.each(&:join)

        # ── 3. Poll for both results ──────────────────────────────────────
        weather = nil
        powerplant = nil
        poll(2) do |r|
          case r['sourceFunction']
          when 'weather'         then weather = r
          when 'powerplantcheck' then powerplant = r
          end
        end

        forecast = weather['forecast']
        deficit_kw = parse_max_deficit(powerplant['powerDeficitKw'])
        log "Forecast entries: #{forecast.size}, power deficit: #{deficit_kw} kW"

        # ── 4. Compute config points ──────────────────────────────────────
        configs = build_configs(forecast, deficit_kw)
        log "Config points: #{configs.size}"
        configs.each { |c| log "  #{c[:date]} #{c[:hour]} pitch=#{c[:pitch]} mode=#{c[:mode]} wind=#{c[:wind]}" }

        # ── 5. Queue unlock codes + turbinecheck in parallel ─────────────
        all_threads = configs.map do |cfg|
          Thread.new do
            api(
              action: 'unlockCodeGenerator',
              startDate: cfg[:date],
              startHour: cfg[:hour],
              windMs: cfg[:wind],
              pitchAngle: cfg[:pitch]
            )
          end
        end
        # Queue turbinecheck now too (will collect result later)
        all_threads << Thread.new { api(action: 'get', param: 'turbinecheck') }
        all_threads.each(&:join)

        # ── 6. Collect unlock codes + turbinecheck result ─────────────────
        codes = {}
        turbine_result = nil
        poll(configs.size + 1) do |r|
          if r['sourceFunction'] == 'unlockCodeGenerator'
            signed = r['signedParams'] || {}
            key = "#{signed['startDate']} #{signed['startHour']}"
            codes[key] = r['unlockCode']
            log "  Unlock code for #{key}: #{codes[key]}"
          elsif r['sourceFunction'] == 'turbinecheck'
            turbine_result = r
            log "  Turbine check: #{r['status']}"
          end
        end

        # ── 7. Send batch config ──────────────────────────────────────────
        batch = {}
        configs.each do |cfg|
          key = "#{cfg[:date]} #{cfg[:hour]}"
          batch[key] = {
            pitchAngle: cfg[:pitch],
            turbineMode: cfg[:mode],
            unlockCode: codes[key]
          }
        end

        config_result = api(action: 'config', configs: batch)
        log "Config result: #{config_result.inspect}"

        # ── 8. Verify ────────────────────────────────────────────────────
        done = api(action: 'done')
        flag = done['message'] || done.to_s
        log "Done: #{done.inspect}"
        log "Flag: #{flag}"

        { verification: done, flag: flag }
      end

      private

      def build_configs(forecast, deficit_kw)
        configs = []
        production_set = false

        forecast.each do |entry|
          wind = entry['windMs'].to_f
          date, hour = entry['timestamp'].split(' ')

          if wind > CUTOFF_WIND_MS
            # Storm protection at the forecast hour
            configs << storm_config(date, hour, wind)
          elsif !production_set && wind >= MIN_WIND_MS
            power = estimate_power(wind, 0)
            log "  Candidate production: #{date} #{hour} wind=#{wind} power=#{power.round(1)} kW (need #{deficit_kw})"
            if power >= deficit_kw
              configs << { date: date, hour: hour, wind: wind, pitch: 0, mode: 'production' }
              production_set = true
            end
          end
        end

        configs
      end

      def storm_config(date, hour, wind)
        { date: date, hour: hour, wind: wind, pitch: 90, mode: 'idle' }
      end

      # Linear interpolation between known yield data points
      WIND_YIELD_POINTS = [
        [0, 0.0], [3.99, 0.0],
        [4, 0.125], [6, 0.35], [8, 0.65], [10, 0.95], [12, 1.0], [14, 1.0]
      ].freeze

      def estimate_power(wind_ms, pitch_deg)
        wind_pct = interpolate_yield(wind_ms)

        pitch_pct = case pitch_deg
                    when 0  then 1.0
                    when 45 then 0.65
                    when 90 then 0.0
                    else 1.0
                    end

        RATED_POWER_KW * wind_pct * pitch_pct
      end

      def interpolate_yield(wind)
        return 0.0 if wind < MIN_WIND_MS || wind > CUTOFF_WIND_MS

        WIND_YIELD_POINTS.each_cons(2) do |(w1, y1), (w2, y2)|
          next unless wind >= w1 && wind <= w2

          return y1 if w1 == w2
          return y1 + (wind - w1) / (w2 - w1) * (y2 - y1)
        end
        0.0
      end

      def parse_max_deficit(val)
        parts = val.to_s.split('-').map(&:to_f)
        parts.max || 3.0
      end

      def poll(expected)
        collected = 0
        attempts = 0
        while collected < expected && attempts < 80
          r = api(action: 'getResult')
          if r['sourceFunction']
            yield r
            collected += 1
          else
            sleep 0.3
          end
          attempts += 1
        end
        raise "Timeout polling results (got #{collected}/#{expected})" if collected < expected
      end

      def api(**params)
        resp = @hub.verify_raw(task: TASK_NAME, answer: params)
        JSON.parse(resp.body)
      end

      def log(msg)
        @log.puts("[windpower] #{msg}")
      end
    end
  end
end
