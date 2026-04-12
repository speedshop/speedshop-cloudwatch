# frozen_string_literal: true

require "speedshop/cloudwatch/puma_observations"

module Speedshop
  module Cloudwatch
    class Puma
      def collect
        PumaObservations.from_stats(::Puma.stats_hash).each do |observation|
          MetricMapper.instance.report(
            metric: observation[:metric],
            value: observation[:value],
            dimensions: observation[:dimensions] || {},
            integration: :puma
          )
        end
      rescue => e
        Speedshop::Cloudwatch.log_error("Failed to collect Puma metrics: #{e.message}", e)
      end
    end
  end
end
