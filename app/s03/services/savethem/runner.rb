# frozen_string_literal: true

module Services
  module Savethem
    class Runner
      TASK_NAME     = 'savethem'
      TARGET_CITY   = 'Skolwin'

      def initialize(hub_client:, tool_client:, logger: $stdout)
        @hub_client  = hub_client
        @tool_client = tool_client
        @logger      = logger
      end

      def call
        log('=== Savethem Agent Starting ===')

        # ── 1. Discover available tools ───────────────────────────────────────────
        tools = discover_tools

        # ── 2. Fetch map ──────────────────────────────────────────────────────────
        map = fetch_map(tools)
        print_map(map)

        # ── 3. Plan optimal route ─────────────────────────────────────────────────
        pathfinder = Pathfinder.new(map: map)
        answer     = pathfinder.best_plan

        raise 'No valid route found! Check map and resource constraints.' unless answer

        log("Planned route (#{answer.length} steps): #{answer.inspect}")

        # ── 4. Submit to verification ─────────────────────────────────────────────
        verification = @hub_client.verify(task: TASK_NAME, answer: answer)
        log("Verification response: #{verification.inspect}")

        flag = extract_flag(verification)
        log("Flag: #{flag}")

        { answer: answer, verification: verification, flag: flag }
      end

      private

      # ── Tool discovery ────────────────────────────────────────────────────────

      def discover_tools
        log('Searching for tools...')
        tools_index = {}

        [
          'map terrain Skolwin',
          'vehicles fuel consumption',
          'movement rules terrain passable'
        ].each do |query|
          results = @tool_client.search(query: query)
          results.each { |t| tools_index[t['name']] = t['url'] }
        end

        log("Found tools: #{tools_index.keys.join(', ')}")
        tools_index
      end

      # ── Map fetching ──────────────────────────────────────────────────────────

      def fetch_map(tools)
        maps_url = tools['maps'] || '/api/maps'
        log("Fetching map for #{TARGET_CITY}...")
        result = @tool_client.call(path: maps_url, query: TARGET_CITY)

        raise "Unexpected map response: #{result.inspect}" unless result['code'].to_i == 241

        grid = result['map']
        raise 'Map data missing from response' unless grid&.any?

        log("Map (#{grid.length}×#{grid[0].length}) loaded, city=#{result['cityName']}")
        grid
      end

      # ── Helpers ───────────────────────────────────────────────────────────────

      def print_map(map)
        map.each_with_index do |row, r|
          log("  row #{r}: #{row.join}")
        end
      end

      def extract_flag(response)
        response['flag'] || response['message'] || response.to_s
      end

      def log(msg)
        @logger.puts("[savethem] #{msg}")
      end
    end
  end
end
