# frozen_string_literal: true

require "speedshop/cloudwatch/active_job_queue_latency"

module Speedshop
  module Cloudwatch
    module ActiveJob
      def self.included(base)
        base.around_perform :report_job_metrics
      end

      def report_job_metrics
        begin
          observation = ActiveJobQueueLatency.for(self)
          if observation
            MetricMapper.instance.report(
              metric: :QueueLatency,
              value: observation[:value],
              dimensions: observation[:dimensions],
              integration: :active_job
            )
          end
        rescue => e
          Speedshop::Cloudwatch.log_error("Failed to collect ActiveJob metrics: #{e.message}", e)
        end
        yield
      end
    end
  end
end
