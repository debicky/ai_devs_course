# frozen_string_literal: true

module Tasks
  class RailwayTask
    def initialize(runner:)
      @runner = runner
    end

    def call
      @runner.call
    end
  end
end

