# frozen_string_literal: true

module Services
  module Domatowo
    class Runner
      TASK_NAME = 'domatowo'

      # Positive indicators in scout inspection logs (Polish)
      # Positive messages contain target-related words like "cel" (target), "mężczyzna" (man),
      # "kontakt" (contact), "odnaleźliśmy" (we found)
      POSITIVE_PHRASES = [
        'mamy cel', 'kontakt z celem', 'mężczyzna', 'kobieta',
        'odnaleźliśmy', 'znaleźliśmy', 'jest tu ktoś', 'żyje'
      ].freeze

      # All B3 (3-floor block) tile groups — the partisan hides in the tallest blocks
      B3_GROUPS = {
        north: { transport_target: 'D1', tiles: %w[F1 G1 G2 F2] },
        south_west: { transport_target: 'B9', tiles: %w[B10 A10 A11 B11 C11 C10] },
        south_east: { transport_target: 'I9', tiles: %w[I10 H10 H11 I11] }
      }.freeze

      def initialize(hub_client:, logger: $stdout)
        @hub = hub_client
        @log = logger
      end

      def call
        log 'Resetting board...'
        api(action: 'reset')

        found_at = search_group(:north, standalone: true) ||
                   search_southern_groups

        unless found_at
          log 'Partisan NOT found in any B3 block!'
          return { verification: nil, flag: nil }
        end

        log "Calling helicopter to #{found_at}..."
        result = api(action: 'callHelicopter', destination: found_at)
        flag = result['message'] || result.to_s
        log "Result: #{result.inspect}"
        log "Flag: #{flag}"

        { verification: result, flag: flag }
      end

      private

      # Search the north group with its own transporter + 1 scout
      def search_group_north
        group = B3_GROUPS[:north]
        transporter_id = create_transporter(passengers: 1)
        move(transporter_id, group[:transport_target])
        dismount(transporter_id, 1)

        scout_id = find_scouts.first
        inspect_tiles(scout_id, group[:tiles])
      end

      # Search a group that has already been set up (scout already on ground)
      def inspect_tiles(scout_id, tiles)
        tiles.each do |tile|
          log "  Scout #{scout_id[0..7]} -> #{tile}"
          api(action: 'move', object: scout_id, where: tile)
          api(action: 'inspect', object: scout_id)
          logs = fetch_logs
          last_log = logs.last
          log "    Log: #{last_log['msg']}" if last_log.is_a?(Hash)
          return tile if last_log && positive_log?(last_log)
        end
        nil
      end

      # Search north group standalone (own transporter)
      def search_group(group_key, standalone: false)
        group = B3_GROUPS[group_key]

        if standalone
          log "Creating transporter for #{group_key}..."
          tid = create_transporter(passengers: 1)
          move(tid, group[:transport_target])
          dismount(tid, 1)
          scout_id = find_scouts.first
        end

        inspect_tiles(scout_id, group[:tiles])
      end

      # Search both southern groups with a shared transporter carrying 2 scouts
      def search_southern_groups
        sw = B3_GROUPS[:south_west]
        se = B3_GROUPS[:south_east]

        log 'Creating transporter for southern groups (2 passengers)...'
        tid = create_transporter(passengers: 2)
        known_scouts = find_scouts.map { |s| s }

        # Drop scout at SW
        move(tid, sw[:transport_target])
        dismount(tid, 1)
        scout2 = (find_scouts - known_scouts).first
        known_scouts << scout2

        # Drop scout at SE
        move(tid, se[:transport_target])
        dismount(tid, 1)
        scout3 = (find_scouts - known_scouts).first

        log "Scout2: #{scout2[0..7]}, Scout3: #{scout3[0..7]}"

        # Search SW then SE
        inspect_tiles(scout2, sw[:tiles]) || inspect_tiles(scout3, se[:tiles])
      end

      # ── API helpers ──────────────────────────────────────────────────────

      def api(**params)
        resp = @hub.verify_raw(task: TASK_NAME, answer: params)
        JSON.parse(resp.body)
      end

      def create_transporter(passengers:)
        api(action: 'create', type: 'transporter', passengers: passengers)
        objects = get_objects
        objects.select { |o| o['typ'] == 'transporter' }.last['id']
      end

      def move(object_id, target)
        api(action: 'move', object: object_id, where: target)
      end

      def dismount(object_id, count)
        api(action: 'dismount', object: object_id, passengers: count)
      end

      def get_objects
        result = api(action: 'getObjects')
        result['objects'] || []
      end

      def find_scouts
        get_objects.select { |o| o['typ'] == 'scout' }.map { |o| o['id'] }
      end

      def fetch_logs
        result = api(action: 'getLogs')
        result['logs'] || []
      end

      def positive_log?(entry)
        msg = (entry.is_a?(Hash) ? entry['msg'] : entry.to_s).downcase
        POSITIVE_PHRASES.any? { |p| msg.include?(p) }
      end

      def log(msg)
        @log.puts("[domatowo] #{msg}")
      end
    end
  end
end
