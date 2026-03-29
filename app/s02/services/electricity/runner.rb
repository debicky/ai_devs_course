# frozen_string_literal: true

require 'tempfile'

module Services
  module Electricity
    class Runner
      TASK_NAME = 'electricity'
      MAX_ATTEMPTS = 5

      def initialize(hub_client:, pixel_solver:)
        @hub    = hub_client
        @solver = pixel_solver
      end

      def call
        # Download solved image once (it's static)
        solved_path = download_solved_image

        attempt = 0
        loop do
          attempt += 1
          raise "Failed after #{MAX_ATTEMPTS} attempts" if attempt > MAX_ATTEMPTS

          puts "\n=== Attempt #{attempt} ==="
          result = run_attempt(solved_path)

          return { verification: result[:last_response], flag: result[:flag] } if result[:flag]

          puts '  No flag yet, retrying...'
        end
      ensure
        File.delete(solved_path) if solved_path && File.exist?(solved_path)
      end

      private

      def download_solved_image
        puts '  Downloading solved image...'
        data = Net::HTTP.get(URI(@hub.solved_electricity_png_url))
        path = File.join(Dir.tmpdir, "solved_electricity_#{Process.pid}.png")
        File.binwrite(path, data)
        puts "  Saved to #{path}"
        path
      end

      def run_attempt(solved_path)
        # Step 1: Reset board
        puts '  Resetting board...'
        @hub.fetch_electricity_png(reset: true)
        puts '  Board reset.'

        # Step 2: Download current board
        puts '  Downloading current board...'
        current_png = @hub.fetch_electricity_png

        # Step 3: Compare pixels to find rotations
        puts '  Computing rotations via pixel comparison...'
        rotations = @solver.solve(current_png, solved_path)

        if rotations.empty?
          puts '  Board already matches target!'
        else
          puts "  Rotations needed: #{rotations}"
          puts "  Total rotate commands: #{rotations.values.sum}"
        end

        # Step 4: Send rotations
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

        { flag: nil, last_response: last_response }
      end

      def extract_flag(response)
        text = response.to_s
        match = text.match(/\{FLG:.*?\}/)
        match&.to_s
      end
    end
  end
end
