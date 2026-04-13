# frozen_string_literal: true

module Speedshop
  module Cloudwatch
    module Observations
      module ActiveJob
        module_function

        def queue_latency(job, now: Time.now.to_f)
          return unless job.enqueued_at

          {
            value: now - job.enqueued_at.to_f,
            dimensions: {QueueName: job.queue_name}
          }
        end
      end
    end
  end
end
