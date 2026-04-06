# frozen_string_literal: true

require 'base64'
require 'tempfile'

module Services
  module Radiomonitoring
    class Runner
      TASK_NAME = 'radiomonitoring'

      MORSE_TABLE = {
        '.-' => 'A', '-...' => 'B', '-.-.' => 'C', '-..' => 'D', '.' => 'E',
        '..-.' => 'F', '--.' => 'G', '....' => 'H', '..' => 'I', '.---' => 'J',
        '-.-' => 'K', '.-..' => 'L', '--' => 'M', '-.' => 'N', '---' => 'O',
        '.--.' => 'P', '--.-' => 'Q', '.-.' => 'R', '...' => 'S', '-' => 'T',
        '..-' => 'U', '...-' => 'V', '.--' => 'W', '-..-' => 'X', '-.--' => 'Y',
        '--..' => 'Z', '.----' => '1', '..---' => '2', '...--' => '3',
        '....-' => '4', '.....' => '5', '-....' => '6', '--...' => '7',
        '---..' => '8', '----.' => '9', '-----' => '0'
      }.freeze

      def initialize(hub_client:, llm_client:, vision_client: nil, whisper_client: nil, logger: $stdout)
        @hub = hub_client
        @llm = llm_client
        @vision = vision_client
        @whisper = whisper_client
        @log = logger
      end

      def call
        log '=== Starting radiomonitoring task ==='

        start_session
        materials = collect_materials
        report = analyze(materials)
        transmit(report)
      end

      private

      # ── Session lifecycle ──────────────────────────────────────────────

      def start_session
        log 'Starting listening session...'
        result = api(action: 'start')
        log "Session: #{result['message']}"
        result
      end

      def collect_materials
        transcriptions = []
        attachments = []
        round = 0

        loop do
          round += 1
          result = api(action: 'listen')
          code = result['code']

          if code != 100
            log "Session ended (code=#{code}): #{result['message']}"
            break
          end

          if result.key?('transcription')
            text = result['transcription']
            if noise?(text)
              log "  [#{round}] NOISE (skipped)"
            else
              log "  [#{round}] TEXT: #{text[0..120]}..."
              transcriptions << text
            end
          elsif result.key?('attachment')
            meta = result['meta']
            size = result['filesize']
            log "  [#{round}] ATTACHMENT: #{meta} (#{size} bytes)"
            attachments << { meta: meta, data: result['attachment'], size: size }
          else
            log "  [#{round}] UNKNOWN: #{result.keys.join(', ')}"
          end
        end

        log "Collected #{transcriptions.size} transcriptions, #{attachments.size} attachments"
        { transcriptions: transcriptions, attachments: attachments }
      end

      # ── Noise detection ────────────────────────────────────────────────

      def noise?(text)
        stripped = text.strip
        return true if stripped.empty?
        return true if stripped.length < 10
        return true if stripped.match?(/\A[\s.\-*#~]+\z/)
        return true if stripped.downcase.match?(/\b(szum|static|noise|brak sygnału|cisza)\b/)

        false
      end

      # ── Morse code ─────────────────────────────────────────────────────

      def morse?(text)
        text.match?(/\b(Ti|Ta)\b/i) && text.match?(/\bstop\b|\(stop\)/i)
      end

      def decode_morse(text)
        # Convert TiTa notation to dots/dashes: Ti=dot, Ta=dash
        # Words separated by (stop), letters separated by spaces
        cleaned = text.gsub(/\*shh+\*\s*/i, '').strip

        words = cleaned.split(/\(stop\)/i).map(&:strip).reject(&:empty?)
        decoded_words = words.map do |word|
          letters = word.split(/\s+/).map do |letter_group|
            morse = letter_group.gsub(/Ti/i, '.').gsub(/Ta/i, '-')
            MORSE_TABLE[morse] || '?'
          end
          letters.join
        end
        decoded_words.join(' ')
      end

      # ── Attachment processing ──────────────────────────────────────────

      def decode_attachment(attachment)
        raw = Base64.decode64(attachment[:data])
        meta = attachment[:meta]

        case meta
        when /json/
          JSON.parse(raw)
        when /csv/, /xml/, /text/, /plain/
          raw.force_encoding('UTF-8')
        when /image/
          { type: 'image', meta: meta, raw: raw }
        when /audio/
          { type: 'audio', meta: meta, raw: raw }
        else
          text = raw.force_encoding('UTF-8')
          text.valid_encoding? ? text : { type: 'binary', meta: meta }
        end
      end

      # ── Analysis ───────────────────────────────────────────────────────

      def analyze(materials)
        all_text_parts = []

        # Process transcriptions — decode Morse if detected
        materials[:transcriptions].each do |text|
          if morse?(text)
            decoded = decode_morse(text)
            log "  MORSE decoded: #{decoded}"
            all_text_parts << "[Morse code decoded]: #{decoded}"
          else
            all_text_parts << text
          end
        end

        # Process attachments
        materials[:attachments].each do |att|
          decoded = decode_attachment(att)

          case decoded
          when String
            unless noise?(decoded)
              log "  Decoded text/CSV/XML attachment (#{decoded.bytesize} bytes)"
              all_text_parts << decoded
            end
          when Hash
            if decoded[:type] == 'image' && @vision
              log '  Analyzing image via vision model...'
              text = analyze_image(decoded[:raw], decoded[:meta])
              all_text_parts << "[Image content]: #{text}" if text && !text.empty?
            elsif decoded[:type] == 'audio' && @whisper
              log '  Transcribing audio...'
              text = transcribe_audio(decoded[:raw])
              all_text_parts << "[Audio transcription]: #{text}" if text && !text.empty?
            elsif decoded[:type] == 'image'
              log '  Skipping image (no vision client)'
            elsif decoded[:type] == 'audio'
              log '  Skipping audio (no whisper client)'
            else
              all_text_parts << JSON.pretty_generate(decoded)
            end
          when Array
            all_text_parts << JSON.pretty_generate(decoded)
          end
        end

        log "Total fragments for analysis: #{all_text_parts.size}"

        if all_text_parts.empty?
          log 'WARNING: No useful materials collected!'
          return {}
        end

        extract_report(all_text_parts)
      end

      def analyze_image(raw_bytes, meta)
        meta.include?('png') ? 'png' : 'jpg'
        b64 = Base64.strict_encode64(raw_bytes)
        data_url = "data:#{meta};base64,#{b64}"

        @vision.extract_text_from_image(
          image_url: data_url,
          prompt: <<~P
            Analyze this image. It may be a map, document, or diagram related to a hidden city called "Syjon".
            Extract ALL text, numbers, names, coordinates, areas, phone numbers, warehouse counts visible.
            Return the extracted information as plain text.
          P
        )
      rescue StandardError => e
        log "  Image analysis failed: #{e.message}"
        nil
      end

      def transcribe_audio(raw_bytes)
        Tempfile.create(['radio', '.mp3']) do |f|
          f.binmode
          f.write(raw_bytes)
          f.flush
          @whisper.transcribe(f.path)
        end
      rescue StandardError => e
        log "  Audio transcription failed: #{e.message}"
        nil
      end

      # ── LLM extraction ────────────────────────────────────────────────

      def extract_report(text_parts)
        combined = text_parts.map.with_index { |t, i| "--- Fragment #{i + 1} ---\n#{t}" }.join("\n\n")

        prompt = <<~PROMPT
          You are analyzing intercepted radio communications to find information about a hidden city called "Syjon" (Zion).
          These are communications from a post-apocalyptic Poland where survivors trade goods between cities.

          From the fragments below, extract:
          1. cityName - the REAL name of the city they call "Syjon" (it's an actual Polish city/town)
          2. cityArea - the area of the city in km², rounded to exactly 2 decimal places (e.g. "12.34")
          3. warehousesCount - the number of warehouses in Syjon (integer)
          4. phoneNumber - the contact phone number for someone in Syjon

          IMPORTANT HINTS:
          - Look carefully at ALL fragments including decoded Morse code, CSV data, JSON data, XML data
          - The Morse code message may contain critical information
          - Structured data (CSV, JSON, XML) may contain city details, areas, phone numbers
          - cityArea must be mathematically rounded to 2 decimal places — use the occupiedArea from the JSON data if available
          - For warehousesCount: count EXISTING warehouses only, NOT planned/future ones. If they say "plan to build the 12th", they currently have 11.
          - Return ONLY a valid JSON object, no markdown fences, no explanations

          Intercepted materials:
          #{combined}
        PROMPT

        log 'Sending materials to LLM for extraction...'
        response = @llm.chat(messages: [{ role: 'user', content: prompt }])
        content = response['content']
        log "LLM raw response: #{content[0..500]}"

        json_str = content.gsub(/\A\s*```json\s*/, '').gsub(/\s*```\s*\z/, '').strip
        report = JSON.parse(json_str)
        report['warehousesCount'] = report['warehousesCount'].to_i

        log "Extracted report: #{report.inspect}"
        report
      end

      # ── Transmit ───────────────────────────────────────────────────────

      def transmit(report)
        log 'Transmitting final report...'
        result = api(
          action: 'transmit',
          cityName: report['cityName'],
          cityArea: report['cityArea'],
          warehousesCount: report['warehousesCount'],
          phoneNumber: report['phoneNumber']
        )
        flag = result['message'] || result.to_s
        log "Result: #{flag}"

        { verification: result, flag: flag }
      end

      # ── Helpers ────────────────────────────────────────────────────────

      def api(**params)
        resp = @hub.verify_raw(task: TASK_NAME, answer: params)
        JSON.parse(resp.body)
      end

      def log(msg)
        @log.puts("[radiomonitoring] #{msg}")
      end
    end
  end
end
