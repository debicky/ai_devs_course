# frozen_string_literal: true

module Clients
  class LlmClient
    OPENAI_BASE_URL = 'https://api.openai.com'
    GEMINI_BASE_URL = 'https://generativelanguage.googleapis.com/v1beta/openai'
    CHAT_PATH       = '/v1/chat/completions'
    MAX_RETRIES     = 3

    TAG_DESCRIPTIONS = {
      'IT' => 'software, programming, computers, IT systems',
      'transport' => 'logistics, moving goods or people, delivery, shipping',
      'edukacja' => 'teaching, tutoring, training, schools',
      'medycyna' => 'healthcare, nursing, diagnostics, therapy',
      'praca z ludźmi' => 'customer service, HR, sales, social work',
      'praca z pojazdami' => 'driving, operating or repairing vehicles',
      'praca fizyczna' => 'manual labor, warehouse, construction, production'
    }.freeze

    def initialize(http_client:, api_key:, model:, base_url: OPENAI_BASE_URL)
      @http_client = http_client
      @api_key     = api_key
      @model       = model
      @base_url    = base_url
    end

    def classify_jobs(records:, allowed_tags:)
      payload = build_classification_payload(records, allowed_tags)
      parsed  = post_chat(payload)
      content = parsed.dig('choices', 0, 'message', 'content')

      raise ArgumentError, "LLM response missing content: #{parsed}" if content.to_s.empty?

      JSON.parse(content)
    end

    def chat_with_tools(messages:, tools:, temperature: nil)
      payload = { model: @model, messages: messages, tools: tools }
      unless omit_temperature?
        payload[:temperature] = temperature.nil? ? 0 : temperature
      end
      # gpt-5-mini / gpt-5.4-nano: omit temperature so API uses its default

      parsed  = post_chat(payload)
      message = parsed.dig('choices', 0, 'message')
      raise ArgumentError, "LLM response missing message: #{parsed}" if message.nil?

      {
        'role' => message['role'] || 'assistant',
        'content' => message['content'],
        'tool_calls' => Array(message['tool_calls'])
      }
    end

    private

    def omit_temperature?
      m = @model.to_s
      m.include?('gpt-5-mini') || m.include?('gpt-5.4-nano')
    end

    def post_chat(payload)
      headers = { 'Authorization' => "Bearer #{@api_key}" }

      retries = 0
      begin
        response = @http_client.post_json("#{@base_url}#{CHAT_PATH}", payload: payload, headers: headers)
        JSON.parse(response.body)
      rescue Clients::HttpError => e
        raise unless e.code == '429' && retries < MAX_RETRIES

        delay = retry_delay(e.message)
        warn "Rate limited. Retrying in #{delay}s... (attempt #{retries + 1}/#{MAX_RETRIES})"
        sleep(delay)
        retries += 1
        retry
      end
    end

    def retry_delay(error_message)
      match = error_message.match(/retry.*?(\d+)s/i)
      match ? match[1].to_i + 2 : 60
    end

    def build_classification_payload(records, allowed_tags)
      {
        model: @model,
        temperature: 0,
        response_format: {
          type: 'json_schema',
          json_schema: {
            name: 'people_jobs_tags',
            strict: true,
            schema: response_schema
          }
        },
        messages: [
          { role: 'system', content: system_prompt(allowed_tags) },
          { role: 'user', content: "Classify these records: #{JSON.generate(records)}" }
        ]
      }
    end

    def system_prompt(allowed_tags)
      tag_lines = allowed_tags.map do |tag|
        description = TAG_DESCRIPTIONS[tag]
        description ? "- #{tag}: #{description}" : "- #{tag}"
      end

      <<~TEXT
        You are a job classifier. Classify each person's job description into zero or more tags.

        Allowed tags:
        #{tag_lines.join("\n")}

        Rules:
        - Use only tags from the list above.
        - A job may have multiple tags or none.
        - Return exactly one result object per input id.
      TEXT
    end

    def response_schema
      {
        type: 'object',
        additionalProperties: false,
        required: ['results'],
        properties: {
          results: {
            type: 'array',
            items: {
              type: 'object',
              additionalProperties: false,
              required: %w[id tags],
              properties: {
                id: { type: 'integer' },
                tags: { type: 'array', items: { type: 'string' } }
              }
            }
          }
        }
      }
    end
  end
end
