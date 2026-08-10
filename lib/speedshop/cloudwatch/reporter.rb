# frozen_string_literal: true

require "singleton"

module Speedshop
  module Cloudwatch
    class Reporter
      MAX_VALUES_PER_DATUM = 150

      include Singleton

      def initialize
        @mutex = Mutex.new
        @condition_variable = ConditionVariable.new
        @queue = []
        @collectors = []
        @thread = nil
        @pid = Process.pid
        @running = false
        @dropped_since_last_flush = 0
        @last_overflow_log = nil
      end

      def start!
        return if !config.environment_enabled? || started?

        @mutex.synchronize do
          return if started?

          reset_after_fork! if forked?
          initialize_collectors

          Speedshop::Cloudwatch.log_info("Starting metric reporter (collectors: #{@collectors.map(&:class).join(", ")})")
          @running = true
          @thread = Thread.new do
            Thread.current.thread_variable_set(:fork_safe, true)
            Thread.current.name = "scw_reporter"
            run_loop
          end
        end
      end

      def started?
        @running && @thread&.alive?
      end

      def stop!
        thread_to_join = nil
        @mutex.synchronize do
          return unless @running
          Speedshop::Cloudwatch.log_info("Stopping metric reporter")
          @running = false
          @condition_variable.signal
          thread_to_join = @thread
          @thread = @pid = nil
          @collectors.clear
        end

        return unless thread_to_join

        result = thread_to_join.join(2)
        if result.nil?
          Speedshop::Cloudwatch.log_info("Reporter thread did not finish within 2s timeout")
        else
          Speedshop::Cloudwatch.log_info("Reporter thread stopped gracefully")
        end
      end

      def enqueue(datum)
        return unless config.environment_enabled?

        @mutex.synchronize do
          reset_after_fork! if forked?

          if @queue.size >= config.queue_max_size
            @queue.shift
            @dropped_since_last_flush += 1
          end
          @queue << datum
        end

        start! unless started?
      end

      def clear_all
        @mutex.synchronize do
          @queue.clear
          @collectors.clear
        end
      end

      # Force immediate metrics collection and flush (for testing)
      # This bypasses the normal interval-based flushing
      def flush_now!
        return unless @running

        collect_metrics
        flush_metrics
      end

      def self.reset
        if instance_variable_defined?(:@singleton__instance__)
          reporter = instance_variable_get(:@singleton__instance__)
          reporter&.stop! if reporter&.started?
          reporter&.clear_all
        end
        instance_variable_set(:@singleton__instance__, nil)
      end

      private

      def config
        Config.instance
      end

      def forked?
        @pid != Process.pid
      end

      def reset_after_fork!
        @collectors.clear
        @queue.clear
        @thread = nil
        @running = false
        @dropped_since_last_flush = 0
        @pid = Process.pid
      end

      def initialize_collectors
        config.collectors.each do |integration|
          @collectors << Speedshop::Cloudwatch::Puma.new if integration == :puma
          @collectors << Speedshop::Cloudwatch::Sidekiq.new if integration == :sidekiq
          @collectors << Speedshop::Cloudwatch::Yabeda::Collector.new if integration == :yabeda
        rescue => e
          Speedshop::Cloudwatch.log_error("Failed to initialize collector for #{integration}: #{e.message}", e)
        end
      end

      def run_loop
        while @running
          @mutex.synchronize do
            @condition_variable.wait(@mutex, config.interval) if @running
          end
          break unless @running
          collect_metrics
          flush_metrics
        end

        flush_metrics
      rescue => e
        Speedshop::Cloudwatch.log_error("Reporter error: #{e.message}", e)
      end

      def collect_metrics
        @collectors.each do |collector|
          collector.collect
        rescue => e
          Speedshop::Cloudwatch.log_error("Collector error: #{e.message}", e)
        end
      end

      def flush_metrics
        metrics = drain_queue
        log_overflow_if_needed
        return unless metrics

        high_resolution = config.interval.to_i < 60
        metrics.group_by { |m| m[:namespace] }.each do |namespace, ns_metrics|
          process_namespace(namespace, ns_metrics, high_resolution)
        end
      rescue => e
        Speedshop::Cloudwatch.log_error("Failed to send metrics: #{e.message}", e)
      end

      def drain_queue
        buf = nil
        @mutex.synchronize do
          return nil if @queue.empty?
          buf = @queue
          @queue = []
        end
        buf
      end

      def process_namespace(namespace, ns_metrics, high_resolution)
        config.logger.debug "Speedshop::Cloudwatch: Sending #{ns_metrics.size} metrics to namespace #{namespace}"
        aggregated = aggregate_namespace_metrics(ns_metrics)
        metric_data = build_metric_data(aggregated, high_resolution)
        send_batches(namespace, metric_data)
      end

      def build_metric_data(aggregated, high_resolution)
        aggregated.map do |m|
          datum = {
            metric_name: m[:metric_name],
            unit: m[:unit],
            timestamp: m[:timestamp],
            dimensions: m[:dimensions]
          }
          if m[:values]
            datum[:values] = m[:values]
            datum[:counts] = m[:counts]
          elsif m[:statistic_values]
            datum[:statistic_values] = m[:statistic_values]
          else
            datum[:value] = m[:value]
          end
          datum[:storage_resolution] = 1 if high_resolution
          datum
        end
      end

      def send_batches(namespace, metric_data)
        metric_data.each_slice(20) do |batch|
          config.client.put_metric_data(namespace: namespace, metric_data: batch)
        end
      end

      def aggregate_namespace_metrics(ns_metrics)
        group_metrics(ns_metrics).flat_map { |items| aggregate_group(items) }
      end

      def group_metrics(ns_metrics)
        groups = {}
        ns_metrics.each do |m|
          key = [
            m[:metric_name],
            m[:unit],
            normalized_dimensions_key(m[:dimensions]),
            m[:aggregation_strategy],
            m.key?(:statistic_values),
            timestamp_bucket(m[:timestamp])
          ]
          (groups[key] ||= []) << m
        end
        groups.values
      end

      def aggregate_group(items)
        return items if items.size == 1

        strategy = items.first[:aggregation_strategy]
        return [items.last] if strategy == :most_recent
        return [items.max_by { |item| item[:value].to_f }] if strategy == :max
        return [merge_statistic_values_group(items)] if items.first[:statistic_values]

        aggregate_distribution_group(items)
      end

      def aggregate_distribution_group(items)
        frequencies = items.each_with_object(Hash.new(0)) do |item, counts|
          counts[item[:value].to_f] += 1
        end

        frequencies.sort_by(&:first).each_slice(MAX_VALUES_PER_DATUM).map do |slice|
          {
            metric_name: items.first[:metric_name],
            unit: items.first[:unit],
            dimensions: items.first[:dimensions],
            timestamp: timestamp_bucket(items.first[:timestamp]),
            values: slice.map(&:first),
            counts: slice.map(&:last)
          }
        end
      end

      def merge_statistic_values_group(items)
        statistic_values = items.map { |item| item[:statistic_values] }
        {
          metric_name: items.first[:metric_name],
          unit: items.first[:unit],
          dimensions: items.first[:dimensions],
          timestamp: timestamp_bucket(items.first[:timestamp]),
          statistic_values: {
            sample_count: statistic_values.sum { |values| values[:sample_count].to_f },
            sum: statistic_values.sum { |values| values[:sum].to_f },
            minimum: statistic_values.map { |values| values[:minimum].to_f }.min,
            maximum: statistic_values.map { |values| values[:maximum].to_f }.max
          }
        }
      end

      def timestamp_bucket(timestamp)
        period = [config.interval.to_i, 1].max
        Time.at((timestamp.to_f / period).floor * period)
      end

      def normalized_dimensions_key(dims)
        (dims || []).sort_by { |d| d[:name].to_s }.map { |d| "#{d[:name]}=#{d[:value]}" }.join("|")
      end

      def log_overflow_if_needed
        dropped = nil
        @mutex.synchronize do
          dropped = @dropped_since_last_flush
          @dropped_since_last_flush = 0
        end
        return unless dropped > 0

        Speedshop::Cloudwatch.log_error("Queue overflow: dropped #{dropped} oldest metric(s) (max queue size: #{config.queue_max_size})")
      end
    end
  end
end
