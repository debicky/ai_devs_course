# frozen_string_literal: true

module Services
  module Electricity
    class RotationSolver
      # Clockwise rotation: U->R, R->D, D->L, L->U
      ROTATE_MAP = { 'U' => 'R', 'R' => 'D', 'D' => 'L', 'L' => 'U' }.freeze

      def solve(current_board, target_board)
        rotations = {}

        current_board.each do |cell, current_edges|
          target_edges = target_board[cell]
          raise "Missing target for cell #{cell}" unless target_edges

          count = rotations_needed(current_edges, target_edges)
          rotations[cell] = count if count.positive?
        end

        rotations
      end

      private

      def rotations_needed(current, target)
        edges = current.dup
        4.times do |n|
          return n if edges == target

          edges = rotate_once(edges)
        end

        raise "Cannot rotate '#{current}' to match '#{target}' in 0-3 steps"
      end

      def rotate_once(edges)
        edges.chars.map { |e| ROTATE_MAP.fetch(e) }.sort.join
      end
    end
  end
end
