# frozen_string_literal: true

module Tasks
  class FindHimTask
    MAX_ITERATIONS = 15
    TASK_NAME = 'findhim'
    SYSTEM_PROMPT = <<~TEXT
      You are solving the AG3NTS task "findhim". Use only these four tools in order.

      Step 1: Call get_suspects once. You get a list of suspects (name, surname, born).

      Step 2: Call get_closest_plant_for_suspect(name, surname) exactly once per suspect from that list. You get closestPlantCode and distanceKm for each. Do not call the same tool with the same arguments twice in one message — call each tool at most once per (name, surname) per turn.

      Step 3: The suspect with the smallest distanceKm is the answer. Call get_access_level(name, surname, birthYear) once for that person — use "born" from get_suspects as birthYear.

      Step 4: Call submit_answer(name, surname, accessLevel, powerPlant). Use the chosen suspect's name and surname; accessLevel from get_access_level (cannot be 0); powerPlant must be the exact closestPlantCode string from step 2 for that suspect. Never use "unknown", a placeholder, or an example code — copy the closestPlantCode value from the tool response verbatim.

      Rules: Call get_closest_plant_for_suspect only once per suspect. After you have all distanceKm values, pick the minimum, then get_access_level for that suspect only, then submit_answer immediately. Do not repeat step 2 or call get_power_plants or get_person_locations.
      CRITICAL: You MUST call the submit_answer tool to finish. When you have the closest suspect and their access level and closestPlantCode, your next response must be a tool call to submit_answer — do not reply with text only. The task is not complete until you call submit_answer.
      If submit_answer returns an error (e.g. "powerPlant cannot be 'unknown'"), you MUST call submit_answer again with the exact closestPlantCode from the get_closest_plant_for_suspect result for that suspect — do not reply with text only.
      Name/surname: Use the exact strings from get_suspects (e.g. Wacław not Waclaw). powerPlant: Must be the exact string from the 'closestPlantCode' key in the get_closest_plant_for_suspect JSON result for that suspect. Never use 'unknown', 'PWR0000PL', or any text that is not that exact code. If a get_closest_plant_for_suspect result contains 'error' instead of 'closestPlantCode', you do not have a valid plant code — do not call submit_answer until you have real closestPlantCode values for each suspect.
    TEXT

    def initialize(llm_client:, tool_executor:)
      @llm_client = llm_client
      @tool_executor = tool_executor
    end

    def call
      messages = [{ role: 'system', content: SYSTEM_PROMPT }]
      state = initial_state
      only_closest_plant_count = 0
      submit_rejected_last_turn = false

      MAX_ITERATIONS.times do |i|
        iteration = i + 1
        if only_closest_plant_count >= 2
          messages << { role: 'user',
                        content: 'You have already called get_closest_plant_for_suspect for all suspects. Look at the tool results above: if they have closestPlantCode and distanceKm, pick the suspect with smallest distanceKm, call get_access_level for that person, then submit_answer with name, surname, accessLevel, and that closestPlantCode. If the results have "error" only, do not call get_closest_plant_for_suspect again — reply in text that plant coordinates are missing.' }
          only_closest_plant_count = 0
        end

        if submit_rejected_last_turn
          messages << { role: 'user',
                        content: 'submit_answer was rejected. Your next message MUST be tool calls: call submit_answer again with the exact closestPlantCode from the get_closest_plant_for_suspect result for your chosen suspect. If you do not have it, call get_closest_plant_for_suspect for that suspect once, then submit_answer with that exact result. Do not reply with text only.' }
          submit_rejected_last_turn = false
        end

        response = @llm_client.chat_with_tools(messages: messages, tools: tool_definitions)
        messages << assistant_message(response)

        yield(iteration, response) if block_given?

        tool_calls = Array(response['tool_calls'])
        if tool_calls.empty? && submit_rejected_last_turn
          # If model replies with no tool calls after rejection, retry immediately with nudge
          messages << { role: 'user',
                        content: 'You just had a submit_answer rejection and replied with no tool calls. You must call submit_answer again with the exact closestPlantCode. Do not reply with text only.' }
          submit_rejected_last_turn = false
          response = @llm_client.chat_with_tools(messages: messages, tools: tool_definitions)
          messages << assistant_message(response)
          yield(iteration, response) if block_given?
          tool_calls = Array(response['tool_calls'])
        end

        if tool_calls.any?
          only_closest = tool_calls.all? { |tc| tc.dig('function', 'name') == 'get_closest_plant_for_suspect' }
          only_closest_plant_count = only_closest ? only_closest_plant_count + 1 : 0
        else
          only_closest_plant_count = 0
        end

        next if tool_calls.empty? && response['content'].to_s.strip.empty?

        next if tool_calls.empty?

        submit_result, tool_results = handle_tool_calls(messages, tool_calls)
        update_state!(state, tool_results)
        guidance = build_guidance_message(state)
        messages << { role: 'user', content: guidance } if guidance
        if tool_results.any? { |tr| tr[:name] == 'submit_answer' && tr[:result].is_a?(Hash) && tr[:result][:error] }
          submit_rejected_last_turn = true
        end
        yield(iteration, response, tool_results) if block_given? && tool_results.any?
        return submit_result if submit_result
      end

      raise "FindHim agent exceeded #{MAX_ITERATIONS} iterations without submitting an answer"
    end

    private

    def handle_tool_calls(messages, tool_calls)
      tool_results = []
      submit_result = nil
      cache = {} # [tool_name, args_key] => result — run each unique (name, args) once per turn

      tool_calls.each do |tool_call|
        tool_name = tool_call.dig('function', 'name').to_s
        arguments = parse_tool_arguments(tool_call.dig('function', 'arguments'))
        args_key = arguments.sort.to_h.to_json
        cache_key = [tool_name, args_key]
        result = cache[cache_key] ||= @tool_executor.call(name: tool_name, arguments: arguments)

        tool_results << { name: tool_name, arguments: arguments, result: result }

        messages << {
          role: 'tool',
          tool_call_id: tool_call['id'],
          content: JSON.generate(result)
        }

        next unless tool_name == 'submit_answer'

        submit_result = result if result[:verification] || result[:incorrect_person]
      end

      [submit_result, tool_results]
    end

    def assistant_message(response)
      message = {
        role: response.fetch('role', 'assistant')
      }

      content = response['content']
      message[:content] = content unless content.nil?

      tool_calls = Array(response['tool_calls'])
      message[:tool_calls] = tool_calls unless tool_calls.empty?

      message
    end

    def parse_tool_arguments(raw_arguments)
      return {} if raw_arguments.to_s.strip.empty?

      JSON.parse(raw_arguments)
    rescue JSON::ParserError => e
      raise ArgumentError, "Tool arguments are not valid JSON: #{e.message}"
    end

    def tool_definitions
      [
        {
          type: 'function',
          function: {
            name: 'get_suspects',
            description: 'Return the list of suspects (name, surname, born). Call once.',
            parameters: empty_parameters
          }
        },
        {
          type: 'function',
          function: {
            name: 'get_closest_plant_for_suspect',
            description: 'For one suspect (name, surname), return closestPlantCode and distanceKm. Call exactly once per suspect.',
            parameters: {
              type: 'object',
              additionalProperties: false,
              required: %w[name surname],
              properties: {
                name: { type: 'string' },
                surname: { type: 'string' }
              }
            }
          }
        },
        {
          type: 'function',
          function: {
            name: 'get_access_level',
            description: 'Return the access level integer for a suspect.',
            parameters: {
              type: 'object',
              additionalProperties: false,
              required: %w[name surname birthYear],
              properties: {
                name: { type: 'string' },
                surname: { type: 'string' },
                birthYear: { type: 'integer' }
              }
            }
          }
        },
        {
          type: 'function',
          function: {
            name: 'submit_answer',
            description: 'Submit the final findhim answer after you identify the closest suspect and access level.',
            parameters: {
              type: 'object',
              additionalProperties: false,
              required: %w[name surname accessLevel powerPlant],
              properties: {
                name: { type: 'string' },
                surname: { type: 'string' },
                accessLevel: { type: 'integer' },
                powerPlant: { type: 'string' }
              }
            }
          }
        }
      ]
    end

    def empty_parameters
      {
        type: 'object',
        additionalProperties: false,
        properties: {}
      }
    end

    def initial_state
      {
        suspects: [],
        closest_results: {},
        access_levels: {}
      }
    end

    def update_state!(state, tool_results)
      tool_results.each do |tool_result|
        case tool_result[:name]
        when 'get_suspects'
          state[:suspects] = Array(tool_result.dig(:result, :suspects))
        when 'get_closest_plant_for_suspect'
          key = suspect_key(tool_result[:arguments]['name'], tool_result[:arguments]['surname'])
          state[:closest_results][key] = tool_result[:result]
        when 'get_access_level'
          key = suspect_key(tool_result[:arguments]['name'], tool_result[:arguments]['surname'])
          state[:access_levels][key] = tool_result.dig(:result, :accessLevel)
        end
      end
    end

    def build_guidance_message(state)
      suspects = state[:suspects]
      return nil if suspects.empty?

      attempted_closest = state[:closest_results]
      return nil if attempted_closest.empty?

      if attempted_closest.size >= suspects.size
        chosen = choose_closest_suspect(state)
        return no_valid_closest_results_message(state) if chosen.nil?

        access_level = state[:access_levels][suspect_key(chosen['name'], chosen['surname'])]
        return submit_guidance_message(chosen, access_level) if access_level

        return access_level_guidance_message(chosen)
      end

      nil
    end

    def choose_closest_suspect(state)
      candidates = state[:suspects].filter_map do |suspect|
        key = suspect_key(suspect['name'], suspect['surname'])
        closest = state[:closest_results][key]
        next unless closest.is_a?(Hash)
        next if closest[:error]
        next unless closest[:closestPlantCode]
        next unless closest[:distanceKm]

        suspect.merge(
          'closestPlantCode' => closest[:closestPlantCode],
          'distanceKm' => closest[:distanceKm]
        )
      end

      candidates.min_by { |candidate| candidate['distanceKm'] }
    end

    def no_valid_closest_results_message(state)
      lines = state[:suspects].map do |suspect|
        key = suspect_key(suspect['name'], suspect['surname'])
        closest = state[:closest_results][key]
        error = closest.is_a?(Hash) ? closest[:error] : 'missing result'
        "- #{suspect['name']} #{suspect['surname']}: #{error}"
      end

      <<~TEXT
        Grounded tool summary: get_closest_plant_for_suspect has already been attempted for all suspects, but none produced a valid closestPlantCode.
        #{lines.join("\n")}
        Do not call submit_answer with placeholders like ERR or PWR0000PL. Only use a real closestPlantCode returned by the tool.
      TEXT
    end

    def access_level_guidance_message(chosen)
      <<~TEXT
        Grounded tool summary: all closest-plant results are already known.
        The smallest valid distance is #{chosen['distanceKm']} km for #{chosen['name']} #{chosen['surname']}.
        The exact closestPlantCode for that suspect is #{chosen['closestPlantCode']}.
        Your next message MUST be exactly one tool call:
        get_access_level(name: #{chosen['name'].inspect}, surname: #{chosen['surname'].inspect}, birthYear: #{Integer(chosen['born'])})
        Do not call get_closest_plant_for_suspect again.
      TEXT
    end

    def submit_guidance_message(chosen, access_level)
      <<~TEXT
        Grounded tool summary: you already have everything needed.
        name=#{chosen['name'].inspect}
        surname=#{chosen['surname'].inspect}
        accessLevel=#{Integer(access_level)}
        powerPlant=#{chosen['closestPlantCode'].inspect}
        Your next message MUST be exactly one submit_answer tool call with those exact values.
        Do not use ERR, PWR0000PL, unknown, or any example code.
      TEXT
    end

    def suspect_key(name, surname)
      "#{name}|#{surname}"
    end
  end
end
