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

      def initialize(llm_client:)
        @llm = llm_client
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
