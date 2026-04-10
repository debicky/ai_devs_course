# frozen_string_literal: true

module Services
  module Timetravel
    # Calculates the temporal sync ratio from a target date.
    #
    # Formula (from CHRONOS-P1 docs):
    #   (day * 8 + month * 12 + year * 7) % 101
    # Result expressed as 0.00–1.00 (two decimal places).
    class SyncRatioCalculator
      DAY_WEIGHT   = 8
      MONTH_WEIGHT = 12
      YEAR_WEIGHT  = 7
      MODULO       = 101

      def call(day:, month:, year:)
        raw = (day * DAY_WEIGHT + month * MONTH_WEIGHT + year * YEAR_WEIGHT) % MODULO
        (raw / 100.0).round(2)
      end
    end
  end
end
