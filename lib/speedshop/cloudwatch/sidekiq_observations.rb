# frozen_string_literal: true

require "sidekiq/api" if defined?(::Sidekiq)

module Speedshop
  module Cloudwatch
    module SidekiqObservations
      module_function

      def collect(sidekiq_queues: Config.instance.sidekiq_queues)
        stats = ::Sidekiq::Stats.new
        processes = ::Sidekiq::ProcessSet.new.to_a

        stat_observations(stats) + utilization_observations(processes) + queue_observations(sidekiq_queues)
      end

      def stat_observations(stats)
        {
          EnqueuedJobs: stats.enqueued,
          ProcessedJobs: stats.processed,
          FailedJobs: stats.failed,
          ScheduledJobs: stats.scheduled_size,
          RetryJobs: stats.retry_size,
          DeadJobs: stats.dead_size,
          Workers: stats.workers_size,
          Processes: stats.processes_size,
          DefaultQueueLatency: stats.default_queue_latency
        }.map do |metric, value|
          {metric: metric, value: value}
        end
      end

      def utilization_observations(processes)
        observations = [{metric: :Capacity, value: processes.sum { |process| process["concurrency"] }}]

        utilization = avg_utilization(processes) * 100.0
        observations << {metric: :Utilization, value: utilization} unless utilization.nan?
        observations
      end

      def queue_observations(sidekiq_queues)
        queues_to_monitor(sidekiq_queues).flat_map do |queue|
          [
            {metric: :QueueLatency, value: queue.latency, dimensions: {QueueName: queue.name}},
            {metric: :QueueSize, value: queue.size, dimensions: {QueueName: queue.name}}
          ]
        end
      end

      def queues_to_monitor(sidekiq_queues)
        all_queues = ::Sidekiq::Queue.all
        return all_queues if sidekiq_queues.nil? || sidekiq_queues.empty?

        all_queues.select { |queue| sidekiq_queues.include?(queue.name) }
      end

      def avg_utilization(processes)
        utils = processes.map { |process| process["busy"] / process["concurrency"].to_f }.reject(&:nan?)
        utils.sum / utils.size.to_f
      end
    end
  end
end
