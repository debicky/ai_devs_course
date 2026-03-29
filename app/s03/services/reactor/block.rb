# frozen_string_literal: true

module Services
  module Reactor
    class Block
      attr_reader :col, :top_row, :bottom_row, :direction

      def initialize(col:, top_row:, bottom_row:, direction:)
        @col        = Integer(col)
        @top_row    = Integer(top_row)
        @bottom_row = Integer(bottom_row)
        @direction  = direction.to_s
      end

      # The hub models each reactor block as a 2-cell vertical bar moving on a 5-row board.
      # Observed cycle per block:
      #   1-2 down -> 2-3 down -> 3-4 down -> 4-5 up -> 3-4 up -> 2-3 up -> 1-2 down
      def step
        if direction == 'down'
          if bottom_row == 4
            self.class.new(col: col, top_row: 4, bottom_row: 5, direction: 'up')
          else
            self.class.new(col: col, top_row: top_row + 1, bottom_row: bottom_row + 1, direction: 'down')
          end
        elsif top_row == 2
          self.class.new(col: col, top_row: 1, bottom_row: 2, direction: 'down')
        else
          self.class.new(col: col, top_row: top_row - 1, bottom_row: bottom_row - 1, direction: 'up')
        end
      end

      def occupies_row?(row)
        top_row <= row && row <= bottom_row
      end
    end
  end
end
