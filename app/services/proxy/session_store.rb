# frozen_string_literal: true

module Services
  module Proxy
    class SessionStore
      DEFAULT_DIRECTORY = File.expand_path('../../../data/proxy_sessions', __dir__)

      def initialize(directory: DEFAULT_DIRECTORY)
        @directory = directory
      end

      def load(session_id)
        path = path_for(session_id)
        return [] unless File.exist?(path)

        data = JSON.parse(File.read(path))
        validate_messages!(data)
        data
      rescue JSON::ParserError => e
        raise ArgumentError, "Invalid session JSON for #{session_id.inspect}: #{e.message}"
      end

      def save(session_id, messages)
        validate_messages!(messages)
        FileUtils.mkdir_p(@directory)
        File.write(path_for(session_id), JSON.pretty_generate(messages))
      end

      def clear(session_id)
        path = path_for(session_id)
        return unless File.exist?(path)

        File.delete(path)
      end

      private

      def path_for(session_id)
        File.join(@directory, "#{safe_session_id(session_id)}.json")
      end

      def safe_session_id(session_id)
        value = session_id.to_s.strip
        raise ArgumentError, 'sessionID must be a non-empty string' if value.empty?

        value.gsub(/[^a-zA-Z0-9_-]/, '_')
      end

      def validate_messages!(messages)
        raise ArgumentError, 'Session messages must be an array' unless messages.is_a?(Array)

        messages.each do |message|
          raise ArgumentError, "Invalid session message: #{message.inspect}" unless message.is_a?(Hash)
        end
      end
    end
  end
end
