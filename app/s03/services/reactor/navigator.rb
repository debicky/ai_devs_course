# frozen_string_literal: true

require 'set'

module Services
  module Reactor
    class Navigator
      Action = Struct.new(:name, :delta, keyword_init: true)

      ACTIONS = [
        Action.new(name: 'left',  delta: -1),
        Action.new(name: 'wait',  delta: 0),
        Action.new(name: 'right', delta: 1)
      ].freeze

      def initialize(initial_state:)
        @initial_state = initial_state
      end

      def plan
        phases = precompute_block_phases(@initial_state.blocks)
        goal_col = Integer(@initial_state.goal_col)
        start_col = Integer(@initial_state.player_col)

        queue = [[start_col, 0, []]]
        seen  = Set[[start_col, 0]]

        until queue.empty?
          col, phase, path = queue.shift
          return path if col == goal_col

          next_phase = (phase + 1) % phases.length
          occupied   = occupied_row_five_cols(phases[next_phase])

          ACTIONS.each do |action|
            new_col = clamp(col + action.delta, min: 1, max: goal_col)
            next if occupied.include?(new_col)

            key = [new_col, next_phase]
            next if seen.include?(key)

            seen << key
            queue << [new_col, next_phase, path + [action.name]]
          end
        end

        raise 'No safe path to reactor goal found from current board state'
      end

      private

      def precompute_block_phases(initial_blocks)
        phases = [initial_blocks]
        5.times { phases << phases.last.map(&:step) }
        phases
      end

      def occupied_row_five_cols(blocks)
        blocks.select { |block| block.occupies_row?(5) }.map(&:col).to_set
      end

      def clamp(value, min:, max:)
        [[value, min].max, max].min
      end
    end
  end
end
