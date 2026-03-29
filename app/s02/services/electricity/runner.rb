# frozen_string_literal: true

module Services
  module Electricity
    class Runner
      TASK_NAME = 'electricity'
      MAX_ATTEMPTS = 5

      def initialize(hub_client:, board_reader:, solver:)
        @hub    = hub_client
        @reader = board_reader
        @solver = solver
      end

      def call
        attempt = 0

        loop do
          attempt += 1
          raise "Failed after #{MAX_ATTEMPTS} attempts" if attempt > MAX_ATTEMPTS

          puts "\n=== Attempt #{attempt} ==="
          result = run_attempt(reset: true)

          return { verification: result[:last_response], flag: result[:flag] } if result[:flag]

          puts '  No flag yet, retrying...'
        end
      end

      private

      def run_attempt(reset:)
        # Step 1: Reset board on first attempt
        if reset
          puts '  Resetting board...'
          @hub.fetch_electricity_png(reset: true)
          puts '  Board reset.'
        end

        # Step 2: Read current board state
        puts '  Reading current board via vision model...'
        current_png = @hub.fetch_electricity_png
        current_board = @reader.read_board(png_data: current_png)
        puts '  Current board:'
        print_board(current_board)

        # Step 3: Read target board state
        puts '  Reading target board via vision model...'
        target_board = @reader.read_board(image_url: @hub.solved_electricity_png_url)
        puts '  Target board:'
        print_board(target_board)

        # Step 4: Compute rotations
        rotations = begin
          @solver.solve(current_board, target_board)
        rescue RuntimeError => e
          puts "  Vision mismatch: #{e.message}"
          puts '  Tile types disagree — re-reading boards on next attempt...'
          return { flag: nil, last_response: nil }
        end

        if rotations.empty?
          puts '  Board already matches target!'
        else
          puts "  Rotations needed: #{rotations}"
          total_rotates = rotations.values.sum
          puts "  Total rotate commands: #{total_rotates}"
        end

        # Step 5: Send rotations
        last_response = nil
        rotations.sort.each do |cell, count|
          count.times do |i|
            puts "  Rotating #{cell} (#{i + 1}/#{count})..."
            last_response = @hub.verify(task: TASK_NAME, answer: { 'rotate' => cell })
            puts "    Hub: #{last_response}"

            flag = extract_flag(last_response)
            return { flag: flag, last_response: last_response } if flag
          end
        end

        # Step 6: Verify — read board again and check
        puts '  Verifying final state...'
        verify_png = @hub.fetch_electricity_png
        final_board = @reader.read_board(png_data: verify_png)
        puts '  Final board:'
        print_board(final_board)

        mismatches = final_board.reject { |cell, edges| target_board[cell] == edges }
        if mismatches.empty?
          puts '  Board matches target! Waiting for flag...'
        else
          puts "  Mismatches remain: #{mismatches}"
        end

        { flag: nil, last_response: last_response }
      end

      def print_board(board)
        (1..3).each do |row|
          cells = (1..3).map { |col| "#{row}x#{col}:#{board["#{row}x#{col}"] || '?'}" }
          puts "    #{cells.join('  ')}"
        end
      end

      def extract_flag(response)
        text = response.to_s
        match = text.match(/\{FLG:.*?\}/)
        match&.to_s
      end
    end
  end
end
