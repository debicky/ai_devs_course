# frozen_string_literal: true

module Services
  module SendIt
    class DeclarationBuilder
      TEMPLATE_PATH = 'zalacznik-E.md'
      BLOCKED_ROUTES_PATH = 'trasy-wylaczone.png'
      MAIN_DOC_PATH = 'index.md'
      STRATEGIC_CATEGORY = 'A'
      FREE_PRICE = '0 PP'
      SYSTEM_FUNDED_LABEL = 'pokrywana przez System'
      CANONICAL_TEMPLATE = <<~TEXT
        SYSTEM PRZESYŁEK KONDUKTORSKICH - DEKLARACJA ZAWARTOŚCI
        ======================================================
        DATA: [YYYY-MM-DD]
        PUNKT NADAWCZY: [miasto nadania]
        ------------------------------------------------------
        NADAWCA: [identyfikator płatnika]
        PUNKT DOCELOWY: [miasto docelowe]
        TRASA: [kod trasy]
        ------------------------------------------------------
        KATEGORIA PRZESYŁKI: A/B/C/D/E
        ------------------------------------------------------
        OPIS ZAWARTOŚCI (max 200 znakw): [...]
        ------------------------------------------------------
        DEKLAROWANA MASA (kg): [...]
        ------------------------------------------------------
        WDP: [liczba]
        ------------------------------------------------------
        UWAGI SPECJALNE: [...]
        ------------------------------------------------------
        KWOTA DO ZAPŁATY: [PP]
        ------------------------------------------------------
        OŚWIADCZAM, ŻE PODANE INFORMACJE SĄ PRAWDZIWE.
        BIORĘ NA SIEBIE KONSEKWENCJĘ ZA FAŁSZYWE OŚWIADCZENIE.
        ======================================================
      TEXT
      ALLOWED_ZARNOWIEC_CATEGORIES = %w[A B].freeze
      STANDARD_CAPACITY_KG = 1000
      EXTRA_WAGON_CAPACITY_KG = 500

      def initialize(today: Date.today)
        @today = today
      end

      def call(documents:, sender_id:, origin:, destination:, weight_kg:, content:, remarks:,
               category: STRATEGIC_CATEGORY)
        validate_documents!(documents)
        validate_category!(category)
        validate_system_funded_rules!(documents, category)
        validate_zarnowiec_rules!(documents, category, destination)

        template = declaration_template(documents)
        route_code = blocked_route_code(documents, origin: origin, destination: destination)
        extra_wagons = extra_wagons_for(weight_kg)

        fill_template(
          template,
          sender_id: sender_id,
          origin: origin,
          destination: destination,
          route_code: route_code,
          category: category,
          content: content,
          weight_kg: weight_kg,
          extra_wagons: extra_wagons,
          remarks: remarks,
          amount: FREE_PRICE
        )
      end

      private

      def validate_documents!(documents)
        return if documents.key?(TEMPLATE_PATH) && documents.key?(BLOCKED_ROUTES_PATH) && documents.key?(MAIN_DOC_PATH)

        raise ArgumentError, 'Missing required SPK documentation attachments for sendit'
      end

      def validate_category!(category)
        return if category == STRATEGIC_CATEGORY

        raise ArgumentError, "Unsupported sendit category: #{category.inspect}"
      end

      def validate_system_funded_rules!(documents, category)
        main_doc = normalized(documents.fetch(MAIN_DOC_PATH).fetch(:content))
        expected = normalized("#{category} - Strategiczna 0 (#{SYSTEM_FUNDED_LABEL})")
        return if main_doc.include?(expected)

        raise ArgumentError, "Could not verify that category #{category} is system-funded in the documentation"
      end

      def validate_zarnowiec_rules!(documents, category, destination)
        destination_name = normalized(destination)
        return unless destination_name.include?('zarnowiec') || destination_name.include?('arnowiec')

        main_doc = normalized(documents.fetch(MAIN_DOC_PATH).fetch(:content))
        route_rule_present = main_doc.include?('trasy prowadzce do arnowca i jego okolic') ||
                             main_doc.include?('trasy prowadzace do zarnowca i jego okolic')
        category_rule_present = main_doc.include?('kategorii a oraz b')

        unless route_rule_present && category_rule_present
          raise ArgumentError, 'Could not verify Żarnowiec special-route restrictions in the documentation'
        end

        return if ALLOWED_ZARNOWIEC_CATEGORIES.include?(category)

        raise ArgumentError, "Category #{category} is not allowed on Żarnowiec routes"
      end

      def declaration_template(documents)
        text = documents.fetch(TEMPLATE_PATH).fetch(:content)
        utf8_text = text.to_s.encode('UTF-8', invalid: :replace, undef: :replace, replace: '')
        template = utf8_text[/```\s*(.*?)\s*```/m, 1]
        return CANONICAL_TEMPLATE if template

        raise ArgumentError, 'Could not extract declaration template from zalacznik-E.md'
      end

      def blocked_route_code(documents, origin:, destination:)
        entries = blocked_routes(documents.fetch(BLOCKED_ROUTES_PATH).fetch(:content))
        target = normalized("#{origin} - #{destination}")

        match = entries.find { |entry| normalized(entry[:route]) == target }
        return match[:code] if match

        raise ArgumentError, "Could not find blocked route code for #{origin} -> #{destination}"
      end

      def blocked_routes(text)
        row_entries = text.lines.map(&:strip).filter_map do |line|
          next unless line.match?(/\AX-\d{2}\b/)

          match = line.match(/\A(?<code>X-\d{2})\s+(?<route>.+?)\s{2,}/)
          next unless match

          { code: match[:code], route: match[:route].strip }
        end
        return row_entries unless row_entries.empty?

        codes = text.scan(/X-\d{2}/)
        path_section = text.split(/Przebieg/i, 2).last.to_s.split(/Powd|Powód/i, 2).first.to_s
        routes = path_section.lines.map(&:strip).reject(&:empty?)

        if codes.empty? || routes.empty? || codes.size != routes.size
          raise ArgumentError, 'Could not parse blocked route OCR output'
        end

        codes.zip(routes).map do |code, route|
          { code: code, route: route }
        end
      end

      def extra_wagons_for(weight_kg)
        weight = Integer(weight_kg)
        return 0 if weight <= STANDARD_CAPACITY_KG

        ((weight - STANDARD_CAPACITY_KG).to_f / EXTRA_WAGON_CAPACITY_KG).ceil
      end

      def fill_template(template, sender_id:, origin:, destination:, route_code:, category:, content:, weight_kg:,
                        extra_wagons:, remarks:, amount:)
        declaration = template.dup
        declaration = replace_line(declaration, 'DATA:', @today.strftime('%Y-%m-%d'))
        declaration = replace_line(declaration, 'PUNKT NADAWCZY:', origin)
        declaration = replace_line(declaration, 'NADAWCA:', sender_id)
        declaration = replace_line(declaration, 'PUNKT DOCELOWY:', destination)
        declaration = replace_line(declaration, 'TRASA:', route_code)
        declaration = replace_line(declaration, 'KATEGORIA PRZESYŁKI:', category)
        declaration = replace_line(declaration, 'OPIS ZAWARTOŚCI (max 200 znakw):', content)
        declaration = replace_line(declaration, 'DEKLAROWANA MASA (kg):', Integer(weight_kg))
        declaration = replace_line(declaration, 'WDP:', extra_wagons)
        declaration = replace_line(declaration, 'UWAGI SPECJALNE:', remarks)
        replace_line(declaration, 'KWOTA DO ZAPŁATY:', amount)
      end

      def replace_line(text, label, value)
        lines = text.lines
        target = normalized(label)
        target_signature = line_signature(label)
        index = lines.index do |line|
          normalized_line = normalized(line)
          normalized_line.start_with?(target) || line_signature(normalized_line) == target_signature
        end
        if index
          prefix = lines[index].to_s.split(':', 2).first.to_s
          lines[index] = "#{prefix}: #{value}\n"
          return lines.join
        end

        raise ArgumentError, "Could not replace template line for #{label}"
      end

      def normalized(text)
        utf8_text = text.to_s.encode('UTF-8', invalid: :replace, undef: :replace, replace: '')
        utf8_text.unicode_normalize(:nfkd).encode('ASCII', replace: '').downcase.gsub(/[^a-z0-9 ]+/, ' ').gsub(/\s+/,
                                                                                                               ' ').strip
      end

      def line_signature(text)
        normalized(text).split.first(3).map { |word| word[0, 6] }.join(' ')
      end
    end
  end
end
