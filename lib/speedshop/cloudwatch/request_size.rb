# frozen_string_literal: true

module Speedshop
  module Cloudwatch
    module RequestSize
      LIMIT = 1024 * 1024

      # Upper bound for uncompressed PutMetricData Query bodies, not Ruby object size.
      # Every supported leaf's full Query key (including MetricData.member.20,
      # Dimensions/Values/Counts indices), '=' and '&' fits within 128 bytes.
      # Percent encoding expands each UTF-8 byte by at most 3. The 64-byte floor
      # covers SDK numeric/timestamp formatting independently of Ruby's to_s.
      # Container overhead is deliberately overcounted, including empty lists.
      def self.bound(value)
        case value
        when Hash
          128 + value.values.sum { |item| bound(item) }
        when Array
          128 + value.sum { |item| bound(item) }
        else
          128 + 3 * [value.to_s.bytesize, 64].max
        end
      end

      def self.request_overhead(namespace)
        # Action, Version, Namespace key, and separators.
        512 + bound(namespace)
      end
    end
  end
end
