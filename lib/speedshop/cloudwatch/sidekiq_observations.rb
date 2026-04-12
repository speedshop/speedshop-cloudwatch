# frozen_string_literal: true

require "speedshop/cloudwatch/observations"

module Speedshop
  module Cloudwatch
    module SidekiqObservations
      module_function

      def collect(sidekiq_queues: Config.instance.sidekiq_queues)
        Observations::Sidekiq.collect(sidekiq_queues: sidekiq_queues)
      end
    end
  end
end
