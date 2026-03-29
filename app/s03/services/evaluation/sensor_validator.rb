# frozen_string_literal: true

module Services
  module Evaluation
    class SensorValidator
      # Maps sensor type name → measurement field name in JSON
      SENSOR_FIELDS = {
        'temperature' => 'temperature_K',
        'pressure' => 'pressure_bar',
        'water' => 'water_level_meters',
        'voltage' => 'voltage_supply_v',
        'humidity' => 'humidity_percent'
      }.freeze

      ALL_FIELDS = SENSOR_FIELDS.values.freeze

      # Valid inclusive ranges for each active sensor field
      VALID_RANGES = {
        'temperature_K' => [553.0, 873.0],
        'pressure_bar' => [60.0, 160.0],
        'water_level_meters' => [5.0, 15.0],
        'voltage_supply_v' => [229.0, 231.0],
        'humidity_percent' => [40.0,  80.0]
      }.freeze

      # Validates a single sensor reading hash.
      # Returns { data_ok: bool, reasons: [String] }
      def validate(data)
        active_types  = data['sensor_type'].to_s.split('/').map(&:strip)
        active_fields = active_types.filter_map { |t| SENSOR_FIELDS[t] }
        inactive_fields = ALL_FIELDS - active_fields

        reasons = []

        # Type 1: active field value must be within valid range
        active_fields.each do |field|
          raw = data[field]
          value = Float(raw)
          min, max = VALID_RANGES[field]
          reasons << "#{field}=#{value} out of range [#{min}, #{max}]" unless value >= min && value <= max
        rescue ArgumentError, TypeError
          reasons << "#{field}: missing or non-numeric (#{raw.inspect})"
        end

        # Type 4: inactive field must be exactly 0 (sensor shouldn't produce this reading)
        inactive_fields.each do |field|
          value = begin
            Float(data[field])
          rescue StandardError
            0.0
          end
          reasons << "#{field}=#{value} is non-zero for inactive sensor" unless value.zero?
        end

        { data_ok: reasons.empty?, reasons: reasons }
      end
    end
  end
end
