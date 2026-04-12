# frozen_string_literal: true

require "speedshop/cloudwatch/observations"

module Speedshop
  module Cloudwatch
    module RequestQueueTime
      module_function

      def from_env(env, now_ms: Observations::Rack.current_time_ms)
        Observations::Rack.request_queue_time(env, now_ms: now_ms)
      end
    end
  end
end
