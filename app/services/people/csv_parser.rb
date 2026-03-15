# frozen_string_literal: true

module Services
  module People
    class CsvParser
      EXPECTED_HEADERS = %w[name surname gender birthDate birthPlace birthCountry job].freeze

      def call(csv_text)
        table = CSV.parse(csv_text.force_encoding('UTF-8'), headers: true)
        validate_headers!(table.headers.map(&:to_s))
        table.each_with_index.map { |row, index| build_person(row, index + 1) }
      end

      private

      def validate_headers!(actual)
        return if actual == EXPECTED_HEADERS

        raise ArgumentError,
              "CSV header mismatch.\n  Expected: #{EXPECTED_HEADERS.inspect}\n  Got:      #{actual.inspect}"
      end

      def build_person(row, id)
        {
          id: id,
          first_name: normalize_text(row['name']),
          last_name: normalize_text(row['surname']),
          gender: normalize_text(row['gender']).downcase,
          city: normalize_text(row['birthPlace']),
          born: extract_year(normalize_text(row['birthDate'])),
          job: normalize_text(row['job'])
        }
      end

      def normalize_text(value)
        value.to_s.encode('UTF-8', invalid: :replace, undef: :replace, replace: '').strip
      end

      def extract_year(birth_date)
        Integer(birth_date.split('-').first)
      rescue ArgumentError
        raise ArgumentError, "Cannot extract year from birthDate: #{birth_date.inspect}"
      end
    end
  end
end
