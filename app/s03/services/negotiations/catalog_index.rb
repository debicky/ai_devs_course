# frozen_string_literal: true

module Services
  module Negotiations
    class CatalogIndex
      FILES = %w[cities.csv items.csv connections.csv].freeze
      CACHE_DIR = File.expand_path('../../../../data/negotiations_catalog', String(__dir__))

      Item = Struct.new(:code, :name, :normalized_name, :tokens, :stem_tokens, keyword_init: true)

      attr_reader :items, :city_name_by_code, :city_codes_by_item_code

      def initialize(hub_client:, logger: $stdout)
        @hub_client = hub_client
        @logger     = logger
      end

      def load
        ensure_cached_files
        load_cities
        load_items
        load_connections
        tap { |_| nil }
      end

      private

      def ensure_cached_files
        FileUtils.mkdir_p(CACHE_DIR)
        FILES.each do |filename|
          path = File.join(CACHE_DIR, filename)
          next if File.exist?(path) && !File.zero?(path)

          log("downloading #{filename}...")
          File.write(path, @hub_client.fetch_negotiations_csv(filename))
        end
      end

      def load_cities
        @city_name_by_code = {}
        csv_rows('cities.csv').each do |row|
          @city_name_by_code[row.fetch('code')] = row.fetch('name')
        end
      end

      def load_items
        @items = csv_rows('items.csv').map do |row|
          name = row.fetch('name')
          Item.new(
            code: row.fetch('code'),
            name: name,
            normalized_name: normalize(name),
            tokens: tokens_for(name),
            stem_tokens: stem_tokens_for(name)
          )
        end
      end

      def load_connections
        @city_codes_by_item_code = Hash.new { |h, k| h[k] = [] }
        csv_rows('connections.csv').each do |row|
          @city_codes_by_item_code[row.fetch('itemCode')] << row.fetch('cityCode')
        end
        @city_codes_by_item_code.each_value(&:uniq!)
      end

      def csv_rows(filename)
        path = File.join(CACHE_DIR, filename)
        CSV.read(path, headers: true).map(&:to_h)
      end

      def normalize(text)
        value = text.to_s.downcase
        transliterate(value)
          .gsub(/[^a-z0-9]+/, ' ')
          .gsub(/\s+/, ' ')
          .strip
      end

      def tokens_for(text)
        normalize(text).split.reject(&:empty?)
      end

      def stem_tokens_for(text)
        tokens_for(text).map { |token| stem_token(token) }
      end

      def stem_token(token)
        value = token.to_s
        if value.length > 4
          value = value.sub(
            /(owej|owego|owych|owym|owac|owaniu|owanie|owego|owego|ania|enie|ami|ach|ego|owy|owa|owe|owej|ymi|ych|ie|em|om|ow|ów|a|y|e|i)\z/, ''
          )
        end
        value
      end

      def transliterate(text)
        text.tr('ąćęłńóśźż', 'acelnoszz')
      end

      def log(message)
        @logger.puts("[negotiations/catalog] #{message}")
      end
    end
  end
end
