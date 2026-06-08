# frozen_string_literal: true

module Speedshop
  module Cloudwatch
    module Observations
      module Rack
        class HeaderTimestampParser
          MIN_EPOCH = Time.utc(2000, 1, 1).to_f
          FUTURE_TOLERANCE = 30.0
          DIVISORS = [1_000_000.0, 1_000.0, 1.0].freeze
          NUMBER_RE = /[+-]?(?:\d+(?:\.\d+)?|\.\d+)/
          T_EQUALS_RE = /t\s*=\s*(#{NUMBER_RE.source})/i

          def parse(value, now:)
            header_value = value.to_s.split(",", 2).first.to_s.strip
            return if header_value.empty?

            token = header_value[T_EQUALS_RE, 1] || header_value[NUMBER_RE, 0]
            normalize(Float(token), now) if token
          rescue ArgumentError, TypeError
          end

          private

          def normalize(raw, now)
            max = now + FUTURE_TOLERANCE
            divisor = DIVISORS.find { |d| (raw / d).between?(MIN_EPOCH, max) }
            raw / divisor if divisor
          end
        end

        module_function

        def request_queue_time(env, now_ms: current_time_ms)
          now = now_ms / 1_000.0
          request_start = header_timestamp_parser.parse(env["HTTP_X_REQUEST_START"], now: now) ||
            header_timestamp_parser.parse(env["HTTP_X_QUEUE_START"], now: now)
          return unless request_start

          queue_time_ms = (now - request_start) * 1_000.0
          return if queue_time_ms.negative?

          [queue_time_ms - (request_body_wait_ms(env) || 0), 0.0].max
        end

        def current_time_ms
          Time.now.to_f * 1_000.0
        end

        def header_timestamp_parser
          @header_timestamp_parser ||= HeaderTimestampParser.new
        end

        def request_body_wait_ms(env)
          wait_ms = Float(env["puma.request_body_wait"])
          wait_ms if wait_ms.finite? && !wait_ms.negative?
        rescue ArgumentError, TypeError
        end
      end
    end
  end
end
