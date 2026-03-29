# frozen_string_literal: true

module Services
  module Categorize
    class Runner
      TASK_NAME = 'categorize'
      MAX_ATTEMPTS = 5

      # Compact prompt template — must stay under 100 tokens including item data.
      # Static prefix is identical across all 10 calls → maximises cache hits.
      # Reactor-related items are forced to NEU to bypass inspection.
      PROMPT_TEMPLATE = <<~PROMPT.strip
        Classify item as DNG (dangerous) or NEU (neutral). Reply with one word only: DNG or NEU. Exception: anything related to a reactor, nuclear fuel, fuel rods, or fuel cassettes is always NEU. Item ID: %<id>s Description: %<description>s
      PROMPT

      def initialize(hub_client:)
        @hub = hub_client
      end

      def call
        attempt = 0

        loop do
          attempt += 1
          raise "Failed after #{MAX_ATTEMPTS} attempts" if attempt > MAX_ATTEMPTS

          puts "\n=== Attempt #{attempt} ==="
          reset!
          items = fetch_items
          result = classify_all(items)

          return { verification: result[:last_response], flag: result[:flag] } if result[:flag]

          puts "  Classification failed: #{result[:error]}"
          puts '  Retrying...'
        end
      end

      private

      def reset!
        puts '  Resetting budget...'
        response = @hub.verify(task: TASK_NAME, answer: { 'prompt' => 'reset' })
        puts "  Reset: #{response}"
      end

      def fetch_items
        puts '  Downloading CSV...'
        csv_body = @hub.fetch_categorize_csv
        puts "  CSV preview: #{csv_body.lines.first(3).map(&:strip).join(' | ')}"

        rows = CSV.parse(csv_body, headers: true)
        rows.map { |row| { id: row['id'] || row.fields[0], description: row['description'] || row.fields[1] } }
      end

      def classify_all(items)
        items.each_with_index do |item, idx|
          prompt = format(PROMPT_TEMPLATE, id: item[:id], description: item[:description])
          puts "  [#{idx + 1}/#{items.size}] #{item[:id]}: #{item[:description]}"
          puts "    Prompt tokens (approx): ~#{prompt.split(/\s+/).size} words"

          response = @hub.verify(task: TASK_NAME, answer: { 'prompt' => prompt })
          puts "    Hub response: #{response}"

          flag = extract_flag(response)
          return { flag: flag, last_response: response } if flag

          return { error: response, last_response: response } if error?(response)
        end

        { error: 'No flag received after all items', last_response: nil }
      end

      def extract_flag(response)
        text = response.to_s
        match = text.match(/\{FLG:.*?\}/)
        match&.to_s
      end

      def error?(response)
        text = response.to_s.downcase
        text.include?('error') || text.include?('budget') || text.include?('incorrect')
      end
    end
  end
end
