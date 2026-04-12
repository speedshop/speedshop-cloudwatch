require "speedshop/cloudwatch/active_job_queue_latency"
require "speedshop/cloudwatch/metrics"
require "speedshop/cloudwatch/puma_observations"
require "speedshop/cloudwatch/request_queue_time"
require "speedshop/cloudwatch/sidekiq_observations"
require "speedshop/cloudwatch/yabeda"

module Smoketest
  module YabedaParity
    module_function

    def setup!
      Yabeda.register_adapter(:cloudwatch, build_adapter)
      configure_metrics
      Yabeda.configure!
    end

    def build_adapter
      Speedshop::Cloudwatch::Yabeda.new(
        metric_name_formatter: ->(metric_name) { camelize(metric_name) },
        allowlist: built_in_allowlist
      )
    end

    def configure_metrics
      Yabeda.configure do
        group :rack do
          histogram :request_queue_time,
            comment: "Time a request spent waiting before reaching Rack",
            unit: :milliseconds,
            buckets: [1, 5, 10, 25, 50, 100, 250, 500, 1000]
        end

        group :active_job do
          histogram :queue_latency,
            comment: "Time a job spent waiting in the queue before execution started",
            tags: %i[QueueName],
            unit: :seconds,
            buckets: [0.001, 0.01, 0.1, 1, 5, 10, 30, 60]
        end

        group :puma do
          gauge :workers, comment: "Configured Puma workers", unit: :count, aggregation: :most_recent
          gauge :booted_workers, comment: "Booted Puma workers", unit: :count, aggregation: :most_recent
          gauge :old_workers, comment: "Old Puma workers", unit: :count, aggregation: :most_recent
          gauge :running, comment: "Running Puma threads", unit: :count
          gauge :backlog, comment: "Backlog per Puma worker", unit: :count
          gauge :pool_capacity, comment: "Pool capacity per Puma worker", unit: :count
          gauge :max_threads, comment: "Max threads per Puma worker", unit: :count

          collect do
            next unless parity_process?("puma")

            Speedshop::Cloudwatch::PumaObservations.from_stats(::Puma.stats_hash).each do |observation|
              report_puma_observation(observation)
            end
          end
        end

        group :sidekiq do
          gauge :enqueued_jobs, comment: "Total enqueued Sidekiq jobs", unit: :count, aggregation: :most_recent
          gauge :processed_jobs, comment: "Total processed Sidekiq jobs", unit: :count, aggregation: :most_recent
          gauge :failed_jobs, comment: "Total failed Sidekiq jobs", unit: :count, aggregation: :most_recent
          gauge :scheduled_jobs, comment: "Scheduled Sidekiq jobs", unit: :count, aggregation: :most_recent
          gauge :retry_jobs, comment: "Retry Sidekiq jobs", unit: :count, aggregation: :most_recent
          gauge :dead_jobs, comment: "Dead Sidekiq jobs", unit: :count, aggregation: :most_recent
          gauge :workers, comment: "Active Sidekiq workers", unit: :count, aggregation: :most_recent
          gauge :processes, comment: "Active Sidekiq processes", unit: :count, aggregation: :most_recent
          gauge :default_queue_latency, comment: "Default queue latency", unit: :seconds, aggregation: :most_recent
          gauge :capacity, comment: "Total Sidekiq capacity", unit: :count, aggregation: :most_recent
          gauge :utilization, comment: "Average Sidekiq utilization", unit: :percent, aggregation: :most_recent
          gauge :queue_latency, comment: "Queue latency by queue", tags: %i[QueueName], unit: :seconds, aggregation: :most_recent
          gauge :queue_size, comment: "Queue size by queue", tags: %i[QueueName], unit: :count, aggregation: :most_recent

          collect do
            next unless parity_process?("sidekiq")

            Speedshop::Cloudwatch::SidekiqObservations.collect.each do |observation|
              report_sidekiq_observation(observation)
            end
          end
        end
      end
    end

    def report_rack_queue_time(env)
      queue_time = Speedshop::Cloudwatch::RequestQueueTime.from_env(env)
      Yabeda.rack.request_queue_time.measure({}, queue_time) if queue_time
    end

    def report_active_job(job)
      observation = Speedshop::Cloudwatch::ActiveJobQueueLatency.for(job)
      return unless observation

      Yabeda.active_job.queue_latency.measure(observation[:dimensions], observation[:value])
    end

    def report_puma_observation(observation)
      metric = Yabeda.puma.public_send(metric_method_name(observation[:metric]))
      metric.set(observation[:dimensions] || {}, observation[:value])
    end

    def report_sidekiq_observation(observation)
      metric = Yabeda.sidekiq.public_send(metric_method_name(observation[:metric]))
      metric.set(observation[:dimensions] || {}, observation[:value])
    end

    def built_in_allowlist
      config = Speedshop::Cloudwatch::Config.instance
      Speedshop::Cloudwatch::METRICS.each_with_object({}) do |(integration, metrics), allowlist|
        allowlist[config.namespaces.fetch(integration)] = metrics.map { |metric| metric.name.to_s }
      end
    end

    def metric_method_name(metric_name)
      metric_name.to_s.gsub(/([A-Z]+)/, '_\\1').downcase.sub(/\A_/, "")
    end

    def camelize(value)
      value.to_s.split("_").map(&:capitalize).join
    end

    def parity_process?(name)
      ENV["SMOKETEST_PROCESS"] == name
    end

    module ActiveJob
      def self.included(base)
        base.around_perform :report_job_metrics_to_yabeda
      end

      def report_job_metrics_to_yabeda
        begin
          Smoketest::YabedaParity.report_active_job(self)
        rescue => e
          Speedshop::Cloudwatch.log_error("Failed to collect Yabeda ActiveJob parity metrics: #{e.message}", e)
        end
        yield
      end
    end

    class RackMiddleware
      def initialize(app)
        @app = app
      end

      def call(env)
        begin
          Smoketest::YabedaParity.report_rack_queue_time(env)
        rescue => e
          Speedshop::Cloudwatch.log_error("Failed to collect Yabeda Rack parity metrics: #{e.message}", e)
        end
        @app.call(env)
      end
    end
  end
end
