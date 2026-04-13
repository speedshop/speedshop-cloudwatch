# frozen_string_literal: true

module Speedshop
  module Cloudwatch
    module Observations
      module Puma
        module_function

        def from_stats(stats)
          if stats[:worker_status]
            clustered_observations(stats)
          else
            single_mode_observations(stats)
          end
        end

        def clustered_observations(stats)
          observations = %i[workers booted_workers old_workers].map do |metric|
            {metric: metric_name_for(metric), value: stats[metric] || 0}
          end

          stats[:worker_status].each do |worker_status|
            last_status = worker_status[:last_status] || {}
            %i[running backlog pool_capacity max_threads].each do |metric|
              next unless last_status.key?(metric)

              observations << {metric: metric_name_for(metric), value: last_status[metric]}
            end
          end

          observations
        end

        def single_mode_observations(stats)
          %i[running backlog pool_capacity max_threads].map do |metric|
            {metric: metric_name_for(metric), value: stats[metric] || 0}
          end
        end

        def metric_name_for(symbol)
          symbol.to_s.split("_").map(&:capitalize).join.to_sym
        end
      end
    end
  end
end
