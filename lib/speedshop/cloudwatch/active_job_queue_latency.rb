# frozen_string_literal: true

module Speedshop
  module Cloudwatch
    module ActiveJobQueueLatency
      module_function

      def for(job, now: Time.now.to_f)
        return unless job.enqueued_at

        {
          value: now - job.enqueued_at.to_f,
          dimensions: {QueueName: job.queue_name}
        }
      end
    end
  end
end
