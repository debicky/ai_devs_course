# frozen_string_literal: true

module Services
  module Mailbox
    class ToolExecutor
      TOOL_NAMES = %w[call_zmail_api submit_answer].freeze

      def initialize(hub_client:)
        @hub_client = hub_client
      end

      def call(name:, arguments:)
        raise ArgumentError, "Unknown tool: #{name}" unless TOOL_NAMES.include?(name)

        public_send(name, arguments)
      end

      def call_zmail_api(arguments)
        action = arguments.fetch('action').to_s.strip
        raise ArgumentError, 'action is required' if action.empty?

        extra = (arguments['params'] || {}).transform_keys(&:to_sym)
        @hub_client.call_zmail(action: action, **extra)
      rescue ArgumentError, KeyError => e
        { error: e.message }
      rescue StandardError => e
        { error: "zmail API error: #{e.message}" }
      end

      def submit_answer(arguments)
        date              = arguments['date'].to_s.strip
        password          = arguments['password'].to_s.strip
        confirmation_code = arguments['confirmation_code'].to_s.strip

        if date.empty? || password.empty? || confirmation_code.empty?
          return { error: 'All three fields (date, password, confirmation_code) are required before submitting.' }
        end

        answer = { date: date, password: password, confirmation_code: confirmation_code }
        body   = @hub_client.verify(task: 'mailbox', answer: answer)

        { verification: body, answer: answer }
      rescue StandardError => e
        { error: "submit error: #{e.message}" }
      end
    end
  end
end
