# frozen_string_literal: true

require "speedshop/cloudwatch/observations"

module Speedshop
  module Cloudwatch
    module ActiveJobQueueLatency
      module_function

      def for(job, now: Time.now.to_f)
        Observations::ActiveJob.queue_latency(job, now: now)
      end
    end
  end
end
