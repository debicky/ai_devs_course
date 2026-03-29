# frozen_string_literal: true

module Services
  module Negotiations
    class SearchTool
      MAX_OUTPUT_BYTES = 500
      MIN_CONFIDENT_SCORE = 180

      def initialize(catalog_index:, logger: $stdout)
        @catalog  = catalog_index
        @matcher  = ItemMatcher.new(catalog_index: catalog_index)
        @logger   = logger
      end

      # Returns a compact plain-text string for the external agent.
      # Supports one item or multiple items separated by commas / semicolons / new lines.
      def call(params:)
        raw = params.to_s.strip
        return fit('Brak parametru.') if raw.empty?

        parts = split_queries(raw)
        resolved = parts.map { |part| resolve(part) }
        confident = resolved.select { |entry| entry[:match] }
        first_ambiguous = resolved.find { |entry| entry[:match].nil? }

        return fit(first_ambiguous[:suggestion_text]) if first_ambiguous
        return fit("Brak dopasowania dla: #{raw}") if confident.empty?

        if confident.length == 1
          item = confident.first[:match].item
          cities = city_names_for_item(item.code)
          text = "Dopasowanie: #{item.name} [#{item.code}]. Miasta: #{cities.join(', ')}"
          return fit(text)
        end

        common = confident.map { |m| city_names_for_item(m[:match].item.code) }
                          .reduce { |acc, names| acc & names }
                          .sort
        items_str = confident.map { |m| "#{m[:match].item.name}[#{m[:match].item.code}]" }.join('; ')
        cities_str = common.empty? ? 'brak' : common.join(', ')
        fit("Pozycje: #{items_str}. Wspolne miasta: #{cities_str}")
      end

      private

      def resolve(query)
        match = @matcher.match(query)
        return suggestion_payload(query) if match.nil? || match.score < MIN_CONFIDENT_SCORE

        { query: query, match: match }
      end

      def suggestion_payload(query)
        suggestions = @matcher.suggestions(query, limit: 3)
        return { query: query, match: nil, suggestion_text: "Brak dopasowania dla: #{query}" } if suggestions.empty?

        suggestion_text = suggestions.map { |m| "#{m.item.name}[#{m.item.code}]" }.join('; ')
        { query: query, match: nil,
          suggestion_text: "Niepewne dopasowanie dla '#{query}'. Najblizsze: #{suggestion_text}" }
      end

      def city_names_for_item(item_code)
        Array(@catalog.city_codes_by_item_code[item_code])
          .map { |code| @catalog.city_name_by_code[code] }
          .compact
          .sort
      end

      def split_queries(raw)
        parts = raw.split(/[\n,;]/).map(&:strip).reject(&:empty?)
        return parts if parts.length > 1

        # Fallback: keep whole natural-language request as a single search query.
        [raw]
      end

      def fit(text)
        out = text.to_s.strip
        out = 'brak' if out.bytesize < 4
        return out if out.bytesize <= MAX_OUTPUT_BYTES

        "#{out.byteslice(0, MAX_OUTPUT_BYTES - 1).to_s.sub(/[^\w\]]*\z/, '')}…"
      end
    end
  end
end
