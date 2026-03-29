# frozen_string_literal: true

module Services
  module People
    class Filter
      TARGET_GENDER = 'm'
      TARGET_CITY   = 'Grudziądz'
      TARGET_YEAR   = 2026
      AGE_RANGE     = (20..40).freeze

      def call(people)
        people.select { |person| eligible?(person) }
      end

      private

      def eligible?(person)
        return false unless person[:gender] == TARGET_GENDER
        return false unless person[:city] == TARGET_CITY

        AGE_RANGE.cover?(age_in_target_year(person))
      end

      def age_in_target_year(person)
        TARGET_YEAR - Integer(person[:born])
      rescue ArgumentError, TypeError
        nil
      end
    end
  end
end
