# frozen_string_literal: true

require 'set'

module Services
  module Negotiations
    class ItemMatcher
      STOPWORDS = %w[
        potrzebuje potrzebujemy szukam szukamy kupie kupic kupna miasto miasta miast gdzie
        da sie moge mozna prosze poprosze chce chcemy dla do oraz albo lub item przedmiot
        przedmiotu przedmioty wszystkich wszystkie jednoczesnie jednocześnie znajdz znajdzcie
        znajdziesz znajdź znajdźcie potrzebny potrzebna potrzebne potrzebnych
      ].to_set.freeze

      Match = Struct.new(:item, :score, keyword_init: true)

      def initialize(catalog_index:)
        @catalog = catalog_index
      end

      def match(query)
        raw_query = query.to_s.strip
        normalized_query = normalize(query)
        query_tokens = normalized_query.split.reject { |token| token.empty? || STOPWORDS.include?(token) }
        query_token_set = query_tokens.to_set
        query_stem_set = query_tokens.map { |token| stem_token(token) }.to_set
        return nil if query_tokens.empty? && normalized_query.empty?

        scored = @catalog.items.map do |item|
          Match.new(item: item,
                    score: score(item, raw_query, normalized_query, query_tokens, query_token_set,
                                 query_stem_set))
        end.reject { |m| m.score <= 0 }

        scored.max_by(&:score)
      end

      def suggestions(query, limit: 3)
        raw_query = query.to_s.strip
        normalized_query = normalize(query)
        query_tokens = normalized_query.split.reject { |token| token.empty? || STOPWORDS.include?(token) }
        query_token_set = query_tokens.to_set
        query_stem_set = query_tokens.map { |token| stem_token(token) }.to_set

        @catalog.items
                .map do |item|
          Match.new(item: item,
                    score: score(
                      item, raw_query, normalized_query, query_tokens, query_token_set, query_stem_set
                    ))
        end
                .sort_by { |m| -m.score }
                .first(limit)
      end

      private

      def score(item, raw_query, normalized_query, query_tokens, query_token_set, query_stem_set)
        return 1_000 if item.code.casecmp?(raw_query)

        score = 0
        item_tokens = item.tokens
        item_token_set = item_tokens.to_set
        item_stem_set = item.stem_tokens.to_set

        score += 700 if item.normalized_name == normalized_query
        score += 500 if !normalized_query.empty? && item.normalized_name.include?(normalized_query)

        overlap = (item_token_set & query_token_set)
        score += overlap.size * 40
        score += 250 if query_token_set.any? && query_token_set.subset?(item_token_set)

        stem_overlap = (item_stem_set & query_stem_set)
        score += stem_overlap.size * 55
        score += 180 if query_stem_set.any? && query_stem_set.subset?(item_stem_set)

        numeric_tokens = query_tokens.select { |t| t.match?(/\d/) }
        numeric_tokens.each do |token|
          score += 60 if item_token_set.include?(token)
        end

        # Common unit variations (e.g. "metrów" → m, "kwh" / "ah" / "v" / "w")
        if (normalized_query.include?('metrow') || normalized_query.include?('metrowy') || normalized_query.include?('metrow')) && item.normalized_name.include?('m ')
          score += 25
        end

        score
      end

      def normalize(text)
        value = text.to_s.downcase
        value.tr('ąćęłńóśźż', 'acelnoszz')
             .gsub(/[^a-z0-9]+/, ' ')
             .gsub(/\s+/, ' ')
             .strip
      end

      def stem_token(token)
        value = token.to_s
        if value.length > 4
          value = value.sub(
            /(owej|owego|owych|owym|owac|owaniu|owanie|ania|enie|ami|ach|ego|owy|owa|owe|ymi|ych|ie|em|om|ow|a|y|e|i)\z/, ''
          )
        end
        value
      end
    end
  end
end
