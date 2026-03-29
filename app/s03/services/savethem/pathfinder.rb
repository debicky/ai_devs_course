# frozen_string_literal: true

require 'set'

module Services
  module Savethem
    # BFS-based pathfinder that respects fuel, food, terrain, and dismount mechanics.
    #
    # State: [row, col, fuel_tenths, food_tenths, mode]
    #   fuel_tenths / food_tenths are Integer (resource × 10) to avoid float errors.
    #
    # Vehicle consumption (× 10):
    #   rocket : fuel=10 (+2 on tree), food=1
    #   car    : fuel=7  (+2 on tree), food=10
    #   horse  : fuel=0,               food=16
    #   walk   : fuel=0,               food=25
    #
    # Water (W) is passable only by horse / walk.
    # Rock  (R) is impassable for everyone.
    # Tree  (T) is passable; powered vehicles pay +0.2 fuel (×10 = +2).
    class Pathfinder
      MOVES = [
        %w[up -1 0],
        %w[down 1 0],
        %w[left 0 -1],
        %w[right 0 1]
      ].freeze

      VEHICLE_COSTS = {
        'rocket' => { fuel: 10, food: 1, tree_fuel_extra: 2 },
        'car' => { fuel: 7, food: 10, tree_fuel_extra: 2 },
        'horse' => { fuel: 0, food: 16, tree_fuel_extra: 0 },
        'walk' => { fuel: 0, food: 25, tree_fuel_extra: 0 }
      }.freeze

      WATER_CAPABLE = %w[horse walk].freeze

      def initialize(map:)
        @map  = map
        @rows = map.length
        @cols = map[0].length
        find_positions
      end

      # Returns the move list (including optional 'dismount') or nil if no path found.
      # Tries rocket first (fastest/most fuel-efficient on food), then others.
      def best_plan
        %w[rocket car horse walk].each do |vehicle|
          result = plan_for(vehicle)
          return result if result
        end
        nil
      end

      # Run BFS for a specific starting vehicle. Returns [vehicle, *moves] or nil.
      def plan_for(start_vehicle)
        start_fuel = 100   # 10.0 × 10
        start_food = 100   # 10.0 × 10

        # queue element: [row, col, fuel, food, mode, path_so_far]
        queue = [[@start_row, @start_col, start_fuel, start_food, start_vehicle, []]]

        # For each (row, col, mode), track best (max) fuel and food seen independently.
        # Prune only when new state is dominated in BOTH dimensions.
        best = Hash.new { |h, k| h[k] = [-1, -1] }
        best[[@start_row, @start_col, start_vehicle]] = [start_fuel, start_food]

        until queue.empty?
          row, col, fuel, food, mode, path = queue.shift

          return [start_vehicle] + path if row == @goal_row && col == @goal_col

          # ── movement ────────────────────────────────────────────────────────────
          MOVES.each do |dir, dr, dc|
            nr = row + dr.to_i
            nc = col + dc.to_i
            next if nr.negative? || nr >= @rows || nc.negative? || nc >= @cols

            cell = @map[nr][nc]
            next if cell == 'R'
            next if cell == 'W' && !WATER_CAPABLE.include?(mode)

            costs      = VEHICLE_COSTS[mode]
            fuel_cost  = costs[:fuel]
            fuel_cost += costs[:tree_fuel_extra] if cell == 'T'
            food_cost  = costs[:food]

            new_fuel = fuel - fuel_cost
            new_food = food - food_cost
            next if new_fuel.negative? || new_food.negative?

            key = [nr, nc, mode]
            bf, bfo = best[key]
            # Prune if dominated in both dimensions
            next if new_fuel <= bf && new_food <= bfo

            # Update best (independently per dimension)
            best[key] = [[new_fuel, bf].max, [new_food, bfo].max]
            queue << [nr, nc, new_fuel, new_food, mode, path + [dir]]
          end

          # ── dismount ─────────────────────────────────────────────────────────────
          next if mode == 'walk' # already on foot

          key = [row, col, 'walk']
          bf, bfo = best[key]
          unless fuel <= bf && food <= bfo
            best[key] = [[fuel, bf].max, [food, bfo].max]
            queue << [row, col, fuel, food, 'walk', path + ['dismount']]
          end
        end

        nil
      end

      private

      def find_positions
        @rows.times do |r|
          @cols.times do |c|
            case @map[r][c]
            when 'S' then @start_row = r
                          @start_col = c
            when 'G' then @goal_row  = r
                          @goal_col  = c
            end
          end
        end
        raise 'Start position (S) not found on map' unless @start_row
        raise 'Goal position (G) not found on map'  unless @goal_row
      end
    end
  end
end
