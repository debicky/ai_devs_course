# frozen_string_literal: true

module Tasks
  class PeopleTask
    def initialize(hub_client:, csv_parser:, people_filter:, job_classifier:, transport_selector:, answer_builder:)
      @hub_client         = hub_client
      @csv_parser         = csv_parser
      @people_filter      = people_filter
      @job_classifier     = job_classifier
      @transport_selector = transport_selector
      @answer_builder     = answer_builder
    end

    def call
      csv_text   = @hub_client.fetch_data('people.csv')
      people     = @csv_parser.call(csv_text)
      filtered   = @people_filter.call(people)
      tags_by_id = @job_classifier.call(filtered)
      with_tags  = merge_tags(filtered, tags_by_id)
      selected   = @transport_selector.call(with_tags)
      answer     = @answer_builder.call(selected)

      @hub_client.verify(task: 'people', answer: answer)
    end

    private

    def merge_tags(people, tags_by_id)
      people.map do |person|
        person.merge(tags: tags_by_id.fetch(Integer(person[:id]), []))
      end
    end
  end
end
