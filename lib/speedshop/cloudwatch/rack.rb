# frozen_string_literal: true

require "speedshop/cloudwatch/request_queue_time"

module Speedshop
  module Cloudwatch
    class Rack
      def initialize(app)
        @app = app
      end

      def call(env)
        begin
          queue_time = RequestQueueTime.from_env(env)
          MetricMapper.instance.report(metric: :RequestQueueTime, value: queue_time) if queue_time
        rescue => e
          Speedshop::Cloudwatch.log_error("Failed to collect Rack metrics: #{e.message}", e)
        end
        @app.call(env)
      end
    end
  end
end
