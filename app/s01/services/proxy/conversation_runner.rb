# frozen_string_literal: true

module Services
  module Proxy
    class ConversationRunner
      MAX_ITERATIONS = 5
      DISCONNECT_MESSAGE = 'DISCONNECT'
      DISCONNECT_REPLY = 'Jasne, dzięki za rozmowę. Gdybyś czegoś potrzebował, daj znać.'
      INTRODUCTION_PATTERNS = [
        /\Awitam\b/i,
        /\Acze(?:ść|sc)\b/i,
        /\Ahej\b/i,
        /\A(?:dzień dobry|dzien dobry)\b/i,
        /\btu\s+[[:alpha:]][[:alpha:]\-ąćęłńóśźż]+/i
      ].freeze
      PACKAGE_ID_PATTERN = /PKG[[:alnum:]]+/i.freeze
      DESTINATION_PATTERN = /PWR\d{4}[A-Z]{2}/.freeze
      SYSTEM_PROMPT = <<~TEXT
        Jesteś pomocnym współpracownikiem działu logistyki.

        Zasady:
        - Odpowiadaj naturalnie i zwięźle.
        - Używaj języka polskiego, chyba że operator pisze w innym języku.
        - Pamiętaj kontekst tej rozmowy w ramach jednej sesji.
        - W sprawach paczek używaj wyłącznie dostępnych narzędzi.
        - Bądź transparentny i precyzyjny.
        - Nigdy nie zmieniaj samodzielnie destination wskazanego przez operatora.
        - Jeśli operator prosi o przekierowanie, użyj dokładnie tego packageid i destination, które podał.
        - Nigdy nie twierdź, że przekierowanie się udało, jeśli narzędzie nie zwróciło sukcesu.
        - Nie ukrywaj błędów API i nie zgaduj brakujących danych.
        - Kod bezpieczeństwa od operatora wolno wykorzystać wyłącznie do dokładnie żądanego przekierowania.
        - Jeśli narzędzie zwróci błąd, opisz go neutralnie i możliwie wiernie względem odpowiedzi API. Nie zgaduj przyczyny poza tym, co zwróciło API.
        - Jeśli wiadomość nie wymaga operacji na paczce, odpowiedz normalnie bez narzędzi.
        - Przy luźnych pytaniach (np. o pogodę, jedzenie, samochody) odpowiadaj swobodnie jak kolega z pracy. Nie mów o braku dostępu, modelu, narzędziach ani ograniczeniach.
      TEXT

      def initialize(llm_client:, tool_executor:, session_store:, logger: $stdout)
        @llm_client = llm_client
        @tool_executor = tool_executor
        @session_store = session_store
        @logger = logger
      end

      def call(session_id:, user_message:)
        session_id = fetch_string(session_id, 'sessionID')
        user_message = fetch_string(user_message, 'msg')
        return handle_disconnect(session_id) if disconnect_message?(user_message)

        reset_stale_session!(session_id, user_message)

        messages = base_messages + @session_store.load(session_id)
        messages << { 'role' => 'user', 'content' => user_message }
        log("session=#{session_id} incoming=#{user_message.inspect}")

        MAX_ITERATIONS.times do |index|
          iteration = index + 1
          response = @llm_client.chat_with_tools(messages: messages, tools: tool_definitions)
          log("session=#{session_id} iteration=#{iteration} assistant=#{response.inspect}")
          messages << assistant_message(response)

          tool_calls = Array(response['tool_calls'])
          if tool_calls.empty?
            reply = response['content'].to_s.strip
            raise ArgumentError, 'LLM returned no content and no tool calls' if reply.empty?

            persist_session(session_id, messages)
            return { 'msg' => reply }
          end

          handle_tool_calls(session_id, messages, tool_calls, iteration)
        end

        raise "Proxy conversation exceeded #{MAX_ITERATIONS} iterations"
      end

      private

      def handle_disconnect(session_id)
        log("session=#{session_id} incoming=#{DISCONNECT_MESSAGE.inspect}")
        @session_store.clear(session_id)
        { 'msg' => DISCONNECT_REPLY }
      end

      def disconnect_message?(user_message)
        user_message.strip.casecmp?(DISCONNECT_MESSAGE)
      end

      def reset_stale_session!(session_id, user_message)
        existing_messages = @session_store.load(session_id)
        return if existing_messages.empty?
        return unless new_session_introduction?(user_message)

        log("session=#{session_id} clearing stale history before new operator introduction")
        @session_store.clear(session_id)
      end

      def new_session_introduction?(user_message)
        INTRODUCTION_PATTERNS.any? { |pattern| user_message.match?(pattern) }
      end

      def base_messages
        [{ 'role' => 'system', 'content' => SYSTEM_PROMPT }]
      end

      def persist_session(session_id, messages)
        conversation = messages.reject { |message| message['role'] == 'system' }
        @session_store.save(session_id, conversation)
      end

      def handle_tool_calls(session_id, messages, tool_calls, iteration)
        cache = {}

        tool_calls.each do |tool_call|
          tool_name = tool_call.dig('function', 'name').to_s
          arguments = parse_tool_arguments(tool_call.dig('function', 'arguments'))
          cache_key = [tool_name, JSON.generate(arguments.sort.to_h)]
          result = cache[cache_key] ||= execute_tool(tool_name, arguments, messages)

          log("session=#{session_id} iteration=#{iteration} tool=#{tool_name} args=#{arguments.inspect} result=#{result.inspect}")
          messages << {
            'role' => 'tool',
            'tool_call_id' => tool_call.fetch('id'),
            'content' => JSON.generate(result)
          }
        end
      end

      def execute_tool(tool_name, arguments, messages)
        if tool_name == 'redirect_package'
          validation_error = validate_redirect_request(arguments, messages)
          return { error: validation_error } if validation_error
        end

        @tool_executor.call(name: tool_name, arguments: arguments)
      end

      def validate_redirect_request(arguments, messages)
        intent = latest_redirect_intent(messages)
        return nil if intent.nil?

        package_id = arguments['packageid'].to_s.strip
        arguments['destination'].to_s.strip

        if intent[:packageid] && package_id != intent[:packageid]
          return "redirect_package must use the exact operator-requested packageid #{intent[:packageid].inspect}, not #{package_id.inspect}"
        end

        nil
      end

      def latest_redirect_intent(messages)
        package_id = nil
        destination = nil

        messages.reverse_each do |message|
          next unless message['role'] == 'user'

          content = message['content'].to_s
          package_id ||= content[PACKAGE_ID_PATTERN]&.upcase
          destination ||= content[DESTINATION_PATTERN]
          break if package_id && destination
        end

        return nil unless package_id || destination

        {
          packageid: package_id,
          destination: destination
        }
      end

      def assistant_message(response)
        message = { 'role' => response.fetch('role', 'assistant') }
        message['content'] = response['content'] unless response['content'].nil?

        tool_calls = Array(response['tool_calls'])
        message['tool_calls'] = tool_calls unless tool_calls.empty?
        message
      end

      def tool_definitions
        [
          {
            type: 'function',
            function: {
              name: 'check_package',
              description: 'Checks package status and package location data by packageid.',
              parameters: {
                type: 'object',
                additionalProperties: false,
                required: ['packageid'],
                properties: {
                  packageid: { type: 'string' }
                }
              }
            }
          },
          {
            type: 'function',
            function: {
              name: 'redirect_package',
              description: 'Redirects a package using the exact destination requested by the operator and the provided security code.',
              parameters: {
                type: 'object',
                additionalProperties: false,
                required: %w[packageid destination code],
                properties: {
                  packageid: { type: 'string' },
                  destination: { type: 'string' },
                  code: { type: 'string' }
                }
              }
            }
          }
        ]
      end

      def parse_tool_arguments(raw_arguments)
        return {} if raw_arguments.to_s.strip.empty?

        JSON.parse(raw_arguments)
      rescue JSON::ParserError => e
        raise ArgumentError, "Tool arguments are not valid JSON: #{e.message}"
      end

      def fetch_string(value, name)
        result = value.to_s.strip
        raise ArgumentError, "#{name} must be a non-empty string" if result.empty?

        result
      end

      def log(message)
        @logger.puts("[proxy] #{message}")
      end
    end
  end
end
