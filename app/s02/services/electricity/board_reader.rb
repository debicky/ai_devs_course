# frozen_string_literal: true

require 'base64'
require 'tempfile'

module Services
  module Electricity
    class BoardReader
      # Directions: U(p), D(own), L(eft), R(ight)
      # Each cell described as sorted set of edges where cables connect.

      VISION_PROMPT = <<~PROMPT
        You are analyzing a 3x3 grid of electrical cable tiles in a PNG image.
        Each tile has cable segments that touch the tile edges: U (up/top), D (down/bottom), L (left), R (right).

        TILE TYPES (each tile is exactly one of these):
        - Straight: 2 opposite edges — either UD (vertical) or LR (horizontal)
        - Corner/curve: 2 adjacent edges — DL, DR, LU, or RU
        - T-junction: 3 edges — DLR, DLU, DRU, or LRU
        - Cross: all 4 edges — DLRU
        - Dead-end: 1 edge — D, L, R, or U
        - Empty: no cable at all — NONE

        IMPORTANT: edges are always sorted alphabetically (D before L before R before U).

        For EACH of the 9 cells (row 1-3 from top, column 1-3 from left), determine which edges have cable connections.

        Trace each cable carefully:
        - Does a cable touch the TOP edge of this cell? → U
        - Does a cable touch the BOTTOM edge? → D
        - Does a cable touch the LEFT edge? → L
        - Does a cable touch the RIGHT edge? → R

        Output format — EXACTLY 9 lines, nothing else:
        1x1: EDGES
        1x2: EDGES
        1x3: EDGES
        2x1: EDGES
        2x2: EDGES
        2x3: EDGES
        3x1: EDGES
        3x2: EDGES
        3x3: EDGES
      PROMPT

      READS_PER_BOARD = 3

      COMPARE_PROMPT = <<~PROMPT
        You are looking at TWO images of 3x3 grids of electrical cable tiles.
        IMAGE 1 is the CURRENT state.
        IMAGE 2 is the TARGET (solved) state.

        Each tile can only be ROTATED 90 degrees clockwise. One rotation maps: U->R, R->D, D->L, L->U.

        IMPORTANT: Since tiles can only be rotated (not replaced), both grids have the SAME tile types at each position.
        Tile types: corner (2 adjacent edges), straight (2 opposite edges), T-junction (3 edges), cross (4 edges).

        For each cell (AxB where A=row 1-3 from top, B=col 1-3 from left):
        1. Identify which edges the cable touches in the CURRENT image: U(top), D(bottom), L(left), R(right)
        2. Identify which edges the cable touches in the TARGET image
        3. Calculate how many 90-degree CLOCKWISE rotations transform current into target (0, 1, 2, or 3)

        Output EXACTLY 9 lines, format: AxB: CURRENT_EDGES -> TARGET_EDGES = N rotations
        Example: 1x1: LU -> DR = 2 rotations

        Sort edges alphabetically (D before L before R before U). Be very precise about which edges cables touch.
      PROMPT

      def initialize(llm_client:)
        @llm = llm_client
      end

      def compare_boards(current_png_data:, target_image_url:)
        b64 = Base64.strict_encode64(current_png_data)
        current_url = "data:image/png;base64,#{b64}"

        readings = READS_PER_BOARD.times.map do |i|
          puts "    Compare read #{i + 1}/#{READS_PER_BOARD}..."
          single_compare(current_url, target_image_url)
        end

        # Majority vote on rotations per cell
        result = {}
        cells = readings.first.keys
        cells.each do |cell|
          votes = readings.map { |r| r[cell] }
          winner = votes.tally.max_by { |_, count| count }.first
          result[cell] = winner
          disagreement = votes.uniq.size > 1
          puts "    #{cell}: #{winner} rots#{" (votes: #{votes.join(', ')})" if disagreement}" if disagreement
        end
        result
      end

      def read_board(png_data: nil, image_url: nil)
        url = if png_data
                b64 = Base64.strict_encode64(png_data)
                "data:image/png;base64,#{b64}"
              elsif image_url
                image_url
              else
                raise ArgumentError, 'Provide png_data or image_url'
              end

        readings = READS_PER_BOARD.times.map do |i|
          puts "    Vision read #{i + 1}/#{READS_PER_BOARD}..."
          single_read(url)
        end

        majority_vote(readings)
      end

      private

      def single_read(url)
        response = @llm.chat(messages: [
                               {
                                 role: 'user',
                                 content: [
                                   { type: 'text', text: VISION_PROMPT },
                                   { type: 'image_url', image_url: { url: url } }
                                 ]
                               }
                             ])

        parse_board(response['content'])
      end

      def single_compare(current_url, target_url)
        response = @llm.chat(messages: [
          {
            role: 'user',
            content: [
              { type: 'text', text: COMPARE_PROMPT },
              { type: 'text', text: 'IMAGE 1 (CURRENT):' },
              { type: 'image_url', image_url: { url: current_url } },
              { type: 'text', text: 'IMAGE 2 (TARGET):' },
              { type: 'image_url', image_url: { url: target_url } }
            ]
          }
        ])

        parse_rotations(response['content'])
      end

      def parse_rotations(text)
        rotations = {}
        text.scan(/(\d)x(\d):.*?=\s*(\d)\s*rotation/i) do |row, col, count|
          rotations["#{row}x#{col}"] = count.to_i
        end
        raise "Expected 9 rotation entries, got #{rotations.size}: #{text}" if rotations.size != 9
        rotations
      end

      def majority_vote(readings)
        board = {}
        all_cells = readings.first.keys

        all_cells.each do |cell|
          votes = readings.map { |r| r[cell] }
          winner = votes.tally.max_by { |_, count| count }.first
          board[cell] = winner
          disagreement = votes.uniq.size > 1
          puts "    #{cell}: #{winner}#{disagreement ? " (votes: #{votes.join(', ')})" : ''}" if disagreement
        end

        board
      end

      def parse_board(text)
        board = {}
        text.scan(/(\d)x(\d):\s*([UDLR]+)/i) do |row, col, edges|
          cell = "#{row}x#{col}"
          board[cell] = edges.upcase.chars.sort.join
        end

        raise "Expected 9 cells, got #{board.size}: #{board}" if board.size != 9

        board
      end
    end
  end
end
