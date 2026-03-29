# frozen_string_literal: true

module Services
  module FindHim
    class DistanceCalculator
      EARTH_RADIUS_KM = 6_371.0

      def call(lat1:, lon1:, lat2:, lon2:)
        latitude_1  = to_radians(lat1)
        longitude_1 = to_radians(lon1)
        latitude_2  = to_radians(lat2)
        longitude_2 = to_radians(lon2)

        latitude_delta  = latitude_2 - latitude_1
        longitude_delta = longitude_2 - longitude_1

        haversine = Math.sin(latitude_delta / 2)**2 +
                    Math.cos(latitude_1) * Math.cos(latitude_2) * Math.sin(longitude_delta / 2)**2

        arc = 2 * Math.atan2(Math.sqrt(haversine), Math.sqrt(1 - haversine))
        EARTH_RADIUS_KM * arc
      end

      private

      def to_radians(value)
        Float(value) * Math::PI / 180
      rescue ArgumentError, TypeError
        raise ArgumentError, "Invalid coordinate value: #{value.inspect}"
      end
    end
  end
end
