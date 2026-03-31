# frozen_string_literal: true

module Tasks
  class ReactorTask
    def initialize(runner:)
      @runner = runner
    end

    def call
      @runner.call
    end
  end
end

