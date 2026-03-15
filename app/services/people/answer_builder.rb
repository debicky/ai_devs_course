# frozen_string_literal: true

module Services
  module People
    class AnswerBuilder
      def call(people)
        people.map { |person| build_row(person) }
      end

      private

      def build_row(person)
        {
          name: person[:first_name],
          surname: person[:last_name],
          gender: person[:gender].upcase,
          born: Integer(person[:born]),
          city: person[:city],
          tags: Array(person[:tags]).map(&:to_s)
        }
      end
    end
  end
end
