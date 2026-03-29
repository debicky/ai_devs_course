# frozen_string_literal: true

require 'set'

module Services
  module Failure
    class Runner
      TASK_NAME            = 'failure'
      MAX_ATTEMPTS         = 8
      INITIAL_TOKEN_BUDGET = 1300
      MIN_TOKEN_BUDGET     = 750
      TOKEN_BUDGET_STEP    = 100
      TAIL_ENTRY_COUNT     = 25
      ENTRY_REGEX          = /\A\[(?<timestamp>\d{4}-\d{2}-\d{2} \d{1,2}:\d{2}:\d{2})\]\s+\[(?<severity>[A-Z]+)\]\s+(?<message>.+)\z/.freeze
      COMPONENT_REGEX      = /\b[A-Z][A-Z0-9_-]{2,}\b/.freeze
      SEVERITY_SCORES      = {
        'INFO' => 0,
        'WARN' => 25,
        'ERRO' => 55,
        'ERROR' => 55,
        'CRIT' => 90,
        'FATAL' => 100
      }.freeze
      COMPONENT_HINTS      = {
        'cool' => %w[ECCS8 WTANK07 WTRPMP WSTPOOL2],
        'coolant' => %w[ECCS8 WTANK07 WTRPMP],
        'water' => %w[WTANK07 WTRPMP],
        'tank' => %w[WTANK07],
        'pump' => %w[WTRPMP],
        'power' => %w[PWR01],
        'steam' => %w[STMTURB12],
        'turbine' => %w[STMTURB12],
        'waste' => %w[WSTPOOL2],
        'software' => %w[FIRMWARE],
        'firmware' => %w[FIRMWARE],
        'eccs' => %w[ECCS8],
        'shutdown' => %w[ECCS8 WTANK07 FIRMWARE],
        'interlock' => %w[ECCS8 FIRMWARE]
      }.freeze
      MESSAGE_REPLACEMENTS = {
        'Automatic correction remains active.' => 'Auto correction active.',
        'Protection interlock initiated reactor trip.' => 'Interlock initiated reactor trip.',
        'Immediate protective actions are required.' => 'Immediate protective action required.',
        'Compensating commands did not recover nominal state.' => 'Compensation did not restore nominal state.',
        'Automatic fallback path has been applied.' => 'Automatic fallback applied.',
        'Protective shutdown path is being enforced.' => 'Protective shutdown enforced.',
        'Cooling reserve may become constrained.' => 'Cooling reserve constrained.',
        'Further recovery attempts are limited.' => 'Further recovery attempts limited.',
        'Immediate shutdown safeguards remain active.' => 'Shutdown safeguards remain active.',
        'Adding an additional power source is strongly recommended.' => 'Additional power source recommended.',
        'Energy conversion is terminated.' => 'Energy conversion terminated.',
        'Emergency interlock keeps the reactor in protected mode.' => 'Emergency interlock keeps protected mode.',
        'FIRMWARE confirms safe shutdown state with all core operations halted.' => 'FIRMWARE confirms safe shutdown; core halted.'
      }.freeze

      def initialize(hub_client:, logger: $stdout)
        @hub_client = hub_client
        @logger     = logger
      end

      def call
        raw_log = @hub_client.fetch_failure_log
        entries = parse_entries(raw_log)
        raise ArgumentError, 'Failure log is empty or could not be parsed' if entries.empty?

        known_components = entries.flat_map { |entry| entry[:components] }.uniq
        token_budget = INITIAL_TOKEN_BUDGET
        required_components = []
        feedback_text = nil
        last_body = nil
        last_logs = nil

        log("loaded #{entries.size} parsed entries")
        log("known components: #{known_components.join(', ')}")

        1.upto(MAX_ATTEMPTS) do |attempt|
          required_components |= infer_components_from_feedback(feedback_text, known_components)
          selected = select_entries(
            entries,
            required_components: required_components,
            feedback_text: feedback_text,
            token_budget: token_budget,
            known_components: known_components
          )
          logs = selected.map { |entry| format_entry(entry) }.join("\n")
          approx = approx_tokens(logs)

          raise ArgumentError, 'Failure task produced an empty logs payload' if logs.empty?

          log("attempt #{attempt}/#{MAX_ATTEMPTS}")
          log("required components: #{required_components.join(', ')}") if required_components.any?
          log("selected #{selected.size} lines (~#{approx} tokens)")

          response = @hub_client.verify_raw(task: TASK_NAME, answer: { logs: logs })
          body = parse_body(response.body)
          last_body = body
          last_logs = logs

          log("hub status=#{response.code}")
          log("hub body=#{format_body(body)}")

          flag = extract_flag(body)
          if flag
            return {
              flag: flag,
              verification: body,
              logs: logs
            }
          end

          if token_limit_error?(response.code, body)
            token_budget -= TOKEN_BUDGET_STEP
            if token_budget < MIN_TOKEN_BUDGET
              raise ArgumentError,
                    'Failure task cannot shrink below minimal token budget'
            end

            log("token limit hit; reducing budget to #{token_budget}")
            next
          end

          raise_unexpected_http_error!(response.code, body) unless response.code == '200'

          feedback_text = extract_feedback_text(body)
          feedback_components = infer_components_from_feedback(feedback_text, known_components)
          required_components |= feedback_components
          log("feedback: #{feedback_text.inspect}")
          log("feedback components: #{feedback_components.join(', ')}") if feedback_components.any?
        end

        raise ArgumentError,
              "Failure task did not reach a flag after #{MAX_ATTEMPTS} attempts. Last response: #{last_body.inspect}\nLast logs:\n#{last_logs}"
      end

      private

      def parse_entries(raw_log)
        raw_log.each_line.with_index.filter_map do |line, index|
          text = line.to_s.strip
          next if text.empty?

          match = text.match(ENTRY_REGEX)
          next unless match

          message = normalize_message(match[:message])
          components = extract_components(message)

          {
            index: index,
            raw: text,
            timestamp: match[:timestamp],
            short_timestamp: match[:timestamp][0, 16],
            severity: match[:severity],
            message: message,
            components: components,
            primary_component: components.first,
            info: match[:severity] == 'INFO',
            non_info: match[:severity] != 'INFO'
          }
        end
      end

      def select_entries(entries, required_components:, feedback_text:, token_budget:, known_components:)
        unique_last_indexes = unique_occurrence_indexes(entries, :last)
        first_component_indexes = first_non_info_indexes(entries)
        tail_indexes = entries.select { |entry| entry[:non_info] }.last(TAIL_ENTRY_COUNT).map { |entry| entry[:index] }
        required_component_set = required_components.to_set
        feedback_terms = feedback_terms(feedback_text)
        known_component_set = known_components.to_set

        ranked = entries.sort_by do |entry|
          [
            -priority_score(
              entry,
              unique_last_indexes: unique_last_indexes,
              first_component_indexes: first_component_indexes,
              tail_indexes: tail_indexes,
              required_component_set: required_component_set,
              feedback_terms: feedback_terms,
              known_component_set: known_component_set
            ),
            entry[:index]
          ]
        end

        chosen = []

        ranked.each do |entry|
          next if chosen.any? { |picked| picked[:index] == entry[:index] }

          tentative = (chosen + [entry]).sort_by { |picked| picked[:index] }
          logs = tentative.map { |picked| format_entry(picked) }.join("\n")
          next if approx_tokens(logs) > token_budget

          chosen = tentative
        end

        chosen = fallback_selection(entries, token_budget) if chosen.empty?
        chosen.sort_by { |entry| entry[:index] }
      end

      def unique_occurrence_indexes(entries, position)
        grouped = entries.select { |entry| entry[:non_info] }.group_by do |entry|
          [entry[:primary_component], entry[:severity], entry[:message]]
        end

        grouped.each_with_object(Set.new) do |(_, grouped_entries), indexes|
          picked = position == :last ? grouped_entries.last : grouped_entries.first
          indexes << picked[:index]
        end
      end

      def first_non_info_indexes(entries)
        entries.select { |entry| entry[:non_info] }
               .group_by { |entry| entry[:primary_component] }
               .values
               .each_with_object(Set.new) do |group, indexes|
          indexes << group.first[:index]
        end
      end

      def priority_score(entry, unique_last_indexes:, first_component_indexes:, tail_indexes:, required_component_set:,
                         feedback_terms:, known_component_set:)
        score = SEVERITY_SCORES.fetch(entry[:severity], 0)
        score += 70 if unique_last_indexes.include?(entry[:index])
        score += 35 if first_component_indexes.include?(entry[:index])
        score += 60 if tail_indexes.include?(entry[:index])

        if (entry[:components] & required_component_set.to_a).any?
          score += entry[:info] ? 30 : 120
        end

        score += 40 if entry[:components].any? { |component| feedback_terms.include?(component.downcase) }

        if feedback_terms.any? && matches_feedback_terms?(entry, feedback_terms)
          score += entry[:info] ? 10 : 35
        end

        score += 5 if entry[:info] && (entry[:components] & known_component_set.to_a).any?

        score
      end

      def fallback_selection(entries, token_budget)
        chosen = []

        entries.select { |entry| entry[:non_info] }.last(TAIL_ENTRY_COUNT).each do |entry|
          tentative = (chosen + [entry]).sort_by { |picked| picked[:index] }
          logs = tentative.map { |picked| format_entry(picked) }.join("\n")
          break if approx_tokens(logs) > token_budget

          chosen = tentative
        end

        chosen
      end

      def infer_components_from_feedback(feedback_text, known_components)
        text = feedback_text.to_s.downcase
        components = extract_components(feedback_text).select { |component| known_components.include?(component) }

        COMPONENT_HINTS.each do |term, mapped_components|
          next unless text.include?(term)

          components.concat(mapped_components)
        end

        components.uniq
      end

      def feedback_terms(feedback_text)
        text = feedback_text.to_s.downcase
        terms = COMPONENT_HINTS.keys.select { |term| text.include?(term) }
        terms.concat(extract_components(feedback_text).map(&:downcase))
        terms.uniq
      end

      def matches_feedback_terms?(entry, feedback_terms)
        haystack = "#{entry[:message]} #{entry[:components].join(' ')}".downcase
        feedback_terms.any? { |term| haystack.include?(term) }
      end

      def extract_components(text)
        text.to_s.scan(COMPONENT_REGEX).uniq.reject do |token|
          token.length < 4 || %w[INFO WARN ERRO CRIT FATAL].include?(token)
        end
      end

      def format_entry(entry)
        "[#{entry[:short_timestamp]}] [#{entry[:severity]}] #{compress_message(entry[:message])}"
      end

      def compress_message(message)
        MESSAGE_REPLACEMENTS.reduce(message.dup) do |text, (source, target)|
          text.gsub(source, target)
        end
      end

      def normalize_message(message)
        message.to_s.gsub(/\s+/, ' ').strip
      end

      def approx_tokens(text)
        words = text.to_s.split(/\s+/).size
        chars = (text.to_s.length / 4.0).ceil
        [words, chars].max
      end

      def parse_body(body)
        JSON.parse(body)
      rescue JSON::ParserError
        { 'raw' => body.to_s }
      end

      def extract_flag(body)
        text = body.is_a?(Hash) || body.is_a?(Array) ? JSON.generate(body) : body.to_s
        match = text.match(/\{FLG:[^}]+\}/)
        match && match[0]
      end

      def extract_feedback_text(body)
        return body.to_s unless body.is_a?(Hash)

        body['message'].to_s.strip
      end

      def token_limit_error?(status_code, body)
        return false unless status_code.to_s == '400'

        extract_feedback_text(body).downcase.include?('1500 token') || extract_feedback_text(body).downcase.include?('too long')
      end

      def raise_unexpected_http_error!(status_code, body)
        return if status_code.to_s == '200'

        raise ArgumentError, "Failure API returned HTTP #{status_code}: #{extract_feedback_text(body)}"
      end

      def format_body(body)
        return JSON.pretty_generate(body) if body.is_a?(Hash) || body.is_a?(Array)

        body.to_s
      end

      def log(message)
        @logger.puts("[failure] #{message}")
      end
    end
  end
end
