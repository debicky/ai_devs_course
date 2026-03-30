# frozen_string_literal: true

require 'tmpdir'
require 'fileutils'

module Services
  module Evaluation
    class Runner
      TASK_NAME = 'evaluation'
      # Cache extracted sensors locally so re-runs skip the download
      SENSORS_CACHE_DIR = File.expand_path('../../../../data/sensors', __dir__)

      def initialize(llm_client:, hub_client:, logger: $stdout)
        @llm_client  = llm_client
        @hub_client  = hub_client
        @validator   = SensorValidator.new
        @classifier  = NoteClassifier.new(llm_client: llm_client, logger: logger)
        @logger      = logger
      end

      def call
        log('Step 1: Fetching sensor data...')
        sensor_dir = fetch_and_extract

        log('Step 2: Parsing and running programmatic validation...')
        records, programmatic_ids = parse_and_validate(sensor_dir)
        log("  Programmatic anomalies (out-of-range / inactive field): #{programmatic_ids.size}")

        log('Step 3: LLM note classification (type-3 anomalies)...')
        note_ids = @classifier.classify(records)
        log("  Note-based anomalies (data-ok but operator claims error): #{note_ids.size}")

        all_ids = (programmatic_ids + note_ids).uniq.sort
        log("Total anomaly IDs to submit: #{all_ids.size}")

        log('Step 4: Submitting to hub...')
        result = @hub_client.verify(task: TASK_NAME, answer: { recheck: all_ids })
        log("  Hub response: #{result.inspect}")

        { anomaly_ids: all_ids, verification: result }
      end

      private

      def fetch_and_extract
        cache = SENSORS_CACHE_DIR
        if File.directory?(cache) && Dir.glob("#{cache}/*.json").size > 100
          count = Dir.glob("#{cache}/*.json").size
          log("  Using cached sensor files (#{count} files in #{cache})")
          return cache
        end

        log('  Downloading sensors.zip...')
        zip_data = @hub_client.get_body('/dane/sensors.zip')
        log("  Downloaded #{zip_data.bytesize} bytes")

        zip_path = File.join(Dir.tmpdir, "sensors_#{Process.pid}.zip")
        File.binwrite(zip_path, zip_data)

        FileUtils.mkdir_p(cache)
        log("  Extracting to #{cache}...")
        raise 'unzip command failed' unless system("unzip -q -o '#{zip_path}' -d '#{cache}'")

        File.delete(zip_path)
        count = Dir.glob("#{cache}/*.json").size
        log("  Extracted #{count} JSON files")
        cache
      end

      def parse_and_validate(sensor_dir)
        files = Dir.glob("#{sensor_dir}/*.json").sort
        records          = []
        programmatic_ids = []

        files.each do |path|
          id   = File.basename(path, '.json')
          data = JSON.parse(File.read(path))
          result = @validator.validate(data)

          programmatic_ids << id unless result[:data_ok]
          records << {
            id: id,
            note: data['operator_notes'].to_s.strip,
            data_ok: result[:data_ok]
          }
        rescue JSON::ParserError => e
          log("  Warning: could not parse #{File.basename(path)}: #{e.message}")
          programmatic_ids << id # treat unparseable file as anomaly
        end

        [records, programmatic_ids]
      end

      def log(msg)
        @logger.puts("[evaluation] #{msg}")
      end
    end
  end
end
