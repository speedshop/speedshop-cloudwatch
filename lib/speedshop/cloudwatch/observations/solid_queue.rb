# frozen_string_literal: true

module Speedshop
  module Cloudwatch
    module Observations
      module SolidQueue
        module_function

        def process_observations(supervisor_id)
          processes = live_worker_processes(supervisor_id)
          return [] if processes.empty?

          observations = [
            {metric: :Processes, value: processes.size},
            {metric: :Workers, value: processes.sum { |process| process.claimed_executions.size }},
            {metric: :Capacity, value: processes.sum { |process| process.metadata["pool_size"] }}
          ]

          utilization = avg_utilization(processes) * 100.0
          observations << {metric: :Utilization, value: utilization} unless utilization.nan?
          observations
        end

        def queue_observations(solid_queue_queues)
          queues_to_monitor(solid_queue_queues).flat_map do |queue|
            [
              {metric: :QueueLatency, value: queue.latency, dimensions: {QueueName: queue.name}},
              {metric: :QueueSize, value: queue.size, dimensions: {QueueName: queue.name}}
            ]
          end
        end

        def queues_to_monitor(solid_queue_queues)
          all_queues = ::SolidQueue::Queue.all
          return all_queues if solid_queue_queues.nil? || solid_queue_queues.empty?

          all_queues.select { |queue| solid_queue_queues.include?(queue.name) }
        end

        def live_worker_processes(supervisor_id)
          ::SolidQueue::Process
            .where(kind: "Worker", supervisor_id: supervisor_id, last_heartbeat_at: ::SolidQueue.process_alive_threshold.ago..)
            .includes(:claimed_executions)
            .to_a
        end

        def avg_utilization(processes)
          utils = processes.map { |process| process.claimed_executions.size / process.metadata["pool_size"].to_f }.reject(&:nan?)
          utils.sum / utils.size.to_f
        end
      end
    end
  end
end
