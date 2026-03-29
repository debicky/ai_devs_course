# frozen_string_literal: true

module Tasks
  class SenditTask
    TASK_NAME = 'sendit'
    SENDER_ID = '450202122'
    ORIGIN = 'Gdańsk'
    DESTINATION = 'Żarnowiec'
    WEIGHT_KG = 2800
    CONTENT = 'kasety z paliwem do reaktora'
    REMARKS = ''
    CATEGORY = 'A'

    def initialize(hub_client:, documentation_explorer:, declaration_builder:)
      @hub_client = hub_client
      @documentation_explorer = documentation_explorer
      @declaration_builder = declaration_builder
    end

    def call
      documents = @documentation_explorer.call
      declaration = @declaration_builder.call(
        documents: documents,
        sender_id: SENDER_ID,
        origin: ORIGIN,
        destination: DESTINATION,
        weight_kg: WEIGHT_KG,
        content: CONTENT,
        remarks: REMARKS,
        category: CATEGORY
      )
      verification = @hub_client.verify(task: TASK_NAME, answer: { declaration: declaration })

      {
        documents: documents,
        declaration: declaration,
        verification: verification
      }
    end
  end
end

