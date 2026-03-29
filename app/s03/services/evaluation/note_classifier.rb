# frozen_string_literal: true

module Services
  module Evaluation
    # Classifies operator_notes for records where data is programmatically OK.
    # Detects type-3 anomalies: data is fine but operator claims there's an error.
    # Deduplicates identical notes to minimise LLM calls and output tokens.
    class NoteClassifier
      BATCH_SIZE = 60

      def initialize(llm_client:, logger: $stdout)
        @llm_client = llm_client
        @logger     = logger
        @cache      = {} # note_text → :claims_error | :claims_ok
      end

      # records: [{ id: String, note: String, data_ok: Boolean }]
      # Returns array of IDs that are type-3 anomalies (data_ok=true, note CLAIMS_ERROR)
      def classify(records)
        # Only files with good data can be type-3 anomalies
        ok_records = records.select { |r| r[:data_ok] }
        log("#{ok_records.size} records have clean data — checking operator notes")

        unique_notes = ok_records.map { |r| r[:note] }.uniq
        log("#{unique_notes.size} unique notes to classify (#{@cache.size} already cached)")

        classify_notes(unique_notes)

        # Cross-reference: data_ok=true + note CLAIMS_ERROR → type-3 anomaly
        ok_records.filter_map do |r|
          r[:id] if @cache[r[:note]] == :claims_error
        end
      end

      private

      def classify_notes(notes)
        uncached = notes.reject { |n| @cache.key?(n) }
        return if uncached.empty?

        total_batches = (uncached.size.to_f / BATCH_SIZE).ceil
        uncached.each_slice(BATCH_SIZE).with_index(1) do |batch, i|
          log("  LLM batch #{i}/#{total_batches} (#{batch.size} notes)...")
          classify_batch(batch)
        end
        log("  Classification complete. Cache now has #{@cache.size} entries.")
      end

      def classify_batch(notes)
        # Number each note so the model returns indices (minimal output)
        numbered = notes.each_with_index.map { |n, i| "#{i}: #{n}" }.join("\n")

        prompt = <<~TEXT
          You are reviewing operator notes from industrial sensor monitoring logs.
          Each note was written by a technician after inspecting sensor readings.

          Classify every note as:
          - "OK"    — technician says readings are fine, normal, stable, no action needed
          - "ERROR" — technician reports a problem, fault, anomaly, deviation, or concern

          Notes (format "index: note text"):
          #{numbered}

          Return ONLY a compact JSON object mapping index strings to "OK" or "ERROR".
          No explanation, no markdown, no code fences. Example: {"0":"OK","1":"ERROR","2":"OK"}
        TEXT

        response = @llm_client.chat(messages: [{ role: 'user', content: prompt }])
        content  = response['content'].to_s.strip
        json_str = content.gsub(/\A```[a-z]*\n?/, '').gsub(/\n?```\z/, '').strip
        parsed   = JSON.parse(json_str)

        notes.each_with_index do |note, i|
          verdict = parsed[i.to_s].to_s.upcase
          @cache[note] = verdict == 'ERROR' ? :claims_error : :claims_ok
        end
      rescue JSON::ParserError => e
        log("  Parse error in batch: #{e.message} — defaulting all to :claims_ok")
        notes.each { |n| @cache[n] ||= :claims_ok }
      end

      def log(msg)
        @logger.puts("[evaluation/notes] #{msg}")
      end
    end
  end
end
