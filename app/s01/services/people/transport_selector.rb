# frozen_string_literal: true

module Services
  module People
    class TransportSelector
      TRANSPORT_TAG = 'transport'

      def call(people)
        people.select { |person| Array(person[:tags]).include?(TRANSPORT_TAG) }
      end
    end
  end
end
