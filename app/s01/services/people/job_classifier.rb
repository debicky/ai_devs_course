# frozen_string_literal: true

module Services
  module People
    class JobClassifier
      ALLOWED_TAGS = [
        'IT',
        'transport',
        'edukacja',
        'medycyna',
        'praca z ludźmi',
        'praca z pojazdami',
        'praca fizyczna'
      ].freeze

      def initialize(llm_client:)
        @llm_client = llm_client
      end

      # Returns { id (Integer) => tags (Array<String>) }
      def call(people)
        return {} if people.empty?

        input = people.map { |p| { id: Integer(p[:id]), job: p[:job].to_s } }
        raw   = @llm_client.classify_jobs(records: input, allowed_tags: ALLOWED_TAGS)
        rows  = raw.fetch('results') { raise KeyError, "LLM response missing 'results' key: #{raw.inspect}" }

        build_tags_by_id(rows)
      end

      private

      def build_tags_by_id(rows)
        rows.each_with_object({}) do |row, acc|
          id   = Integer(row.fetch('id'))
          tags = Array(row.fetch('tags'))
                 .map(&:to_s)
                 .select { |tag| ALLOWED_TAGS.include?(tag) }
                 .uniq

          acc[id] = tags
        end
      end
    end
  end
end
