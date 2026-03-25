# frozen_string_literal: true

module Tasks
  class ProxyTask
    def initialize(http_server:)
      @http_server = http_server
    end

    def call
      @http_server.start
    end
  end
end

