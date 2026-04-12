# frozen_string_literal: true

require "speedshop/cloudwatch/observations"

module Speedshop
  module Cloudwatch
    module ActiveJob
      def self.included(base)
        base.around_perform :report_job_metrics
      end

      def report_job_metrics
        begin
          observation = Observations::ActiveJob.queue_latency(self)
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
