# frozen_string_literal: true

module Services
  module FindHim
    class SuspectsLoader
      REQUIRED_KEYS = %w[name surname born].freeze

      def initialize(file_path:)
        @file_path = file_path
      end

      def call
        data = parse_file
        validate_root!(data)

        data.map.with_index do |row, index|
          normalize_suspect(row, index)
        end
      end

      private

      def parse_file
        JSON.parse(File.read(@file_path))
      rescue Errno::ENOENT
        raise ArgumentError, "Suspects file not found: #{@file_path}"
      rescue JSON::ParserError => e
        raise ArgumentError, "Invalid suspects JSON in #{@file_path}: #{e.message}"
      end

      def validate_root!(data)
        return if data.is_a?(Array)

        raise ArgumentError, "Suspects file must contain a JSON array: #{@file_path}"
      end

      def normalize_suspect(row, index)
        raise ArgumentError, "Suspect at index #{index} must be a JSON object" unless row.is_a?(Hash)

        missing_keys = REQUIRED_KEYS.reject { |key| row.key?(key) }
        unless missing_keys.empty?
          raise ArgumentError, "Suspect at index #{index} is missing keys: #{missing_keys.join(', ')}"
        end

        {
          'name' => row.fetch('name').to_s.strip,
          'surname' => row.fetch('surname').to_s.strip,
          'born' => Integer(row.fetch('born'))
        }
      rescue ArgumentError, TypeError
        raise ArgumentError, "Suspect at index #{index} has invalid data: #{row.inspect}"
      end
    end
  end
end
