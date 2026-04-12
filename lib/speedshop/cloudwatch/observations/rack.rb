# frozen_string_literal: true

module Speedshop
  module Cloudwatch
    module Observations
      module Rack
        module_function

        def request_queue_time(env, now_ms: current_time_ms)
          header = env["HTTP_X_REQUEST_START"] || env["HTTP_X_QUEUE_START"]
          return unless header

          now_ms - header.gsub("t=", "").to_f
        end

        def current_time_ms
          Time.now.to_f * 1000
        end
      end
    end
  end
end
