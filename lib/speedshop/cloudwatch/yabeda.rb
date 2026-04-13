# frozen_string_literal: true

require "speedshop/cloudwatch"

begin
  require "yabeda" unless defined?(::Yabeda)
rescue LoadError => e
  if e.path == "yabeda"
    raise LoadError, "speedshop/cloudwatch/yabeda requires the `yabeda` gem. Add `gem \"yabeda\"` to your Gemfile."
  end

  raise
end

module Speedshop
  module Cloudwatch
    class Yabeda < ::Yabeda::BaseAdapter
      UNIT_MAP = {
        seconds: "Seconds",
        milliseconds: "Milliseconds",
        microseconds: "Microseconds",
        bytes: "Bytes",
        kilobytes: "Kilobytes",
        megabytes: "Megabytes",
        gigabytes: "Gigabytes",
        terabytes: "Terabytes",
        bits: "Bits",
        kilobits: "Kilobits",
        megabits: "Megabits",
        gigabits: "Gigabits",
        terabits: "Terabits",
        percent: "Percent",
        count: "Count"
      }.freeze

      def initialize(namespace_formatter: nil, metric_name_formatter: nil, dimension_name_formatter: nil, allowlist: nil)
        @namespace_formatter = namespace_formatter
        @metric_name_formatter = metric_name_formatter
        @dimension_name_formatter = dimension_name_formatter
        @allowlist = normalize_allowlist(allowlist)

        Speedshop::Cloudwatch.configure do |config|
          config.collectors << :yabeda unless config.collectors.include?(:yabeda)
        end
      end

      # CloudWatch doesn't require pre-registration of metrics, but Yabeda's adapter
      # interface expects these hooks to exist for backends that do.
      def register_counter!(_metric)
      end

      def register_gauge!(_metric)
      end

      def register_histogram!(_metric)
      end

      def register_summary!(_metric)
      end

      def perform_counter_increment!(counter, tags, increment)
        enqueue_metric(counter, tags, increment)
      end

      def perform_gauge_set!(gauge, tags, value)
        enqueue_metric(gauge, tags, value)
      end

      def perform_histogram_measure!(histogram, tags, value)
        enqueue_metric(histogram, tags, value)
      end

      def perform_summary_observe!(summary, tags, value)
        enqueue_metric(summary, tags, value)
      end

      class Collector
        def collect
          ::Yabeda.collect!
        end
      end

      private

      def enqueue_metric(metric, tags, value)
        namespace = namespace_for(metric)
        metric_name = metric_name_for(metric)
        return unless allowed?(namespace, metric_name)

        Reporter.instance.enqueue(
          metric_name: metric_name,
          namespace: namespace,
          unit: unit_for(metric),
          dimensions: dimensions_for(tags),
          value: value,
          timestamp: Time.now,
          aggregation_strategy: aggregation_strategy_for(metric)
        )
      end

      def namespace_for(metric)
        format_value(metric.group.to_s.split("_").map(&:capitalize).join, @namespace_formatter, metric)
      end

      def metric_name_for(metric)
        format_value(metric.name.to_s, @metric_name_formatter, metric)
      end

      def unit_for(metric)
        UNIT_MAP.fetch(metric.unit&.to_sym, "None")
      end

      def dimensions_for(tags)
        tag_dimensions = tags.to_h.map do |name, value|
          {name: format_value(name.to_s, @dimension_name_formatter), value: value.to_s}
        end
        tag_dimensions + Config.instance.dimensions.map do |name, value|
          {name: format_value(name.to_s, @dimension_name_formatter), value: value.to_s}
        end
      end

      def aggregation_strategy_for(metric)
        return unless metric.is_a?(::Yabeda::Gauge)

        strategy = metric.aggregation&.to_sym
        strategy if %i[most_recent max].include?(strategy)
      end

      def allowed?(namespace, metric_name)
        return true unless @allowlist

        Array(@allowlist[namespace]).map(&:to_s).include?(metric_name.to_s)
      end

      def normalize_allowlist(allowlist)
        return unless allowlist

        allowlist.each_with_object({}) do |(namespace, metrics), normalized|
          normalized[namespace.to_s] = Array(metrics).map(&:to_s)
        end
      end

      def format_value(value, formatter, metric = nil)
        return value unless formatter

        (formatter.arity == 1) ? formatter.call(value) : formatter.call(value, metric)
      end
    end
  end
end
