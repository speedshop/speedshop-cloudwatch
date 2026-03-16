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

      def initialize
        Speedshop::Cloudwatch.configure do |config|
          config.collectors << :yabeda unless config.collectors.include?(:yabeda)
        end
      end

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
        Reporter.instance.enqueue(
          metric_name: metric.name.to_s,
          namespace: namespace_for(metric),
          unit: unit_for(metric),
          dimensions: dimensions_for(tags),
          value: value,
          timestamp: Time.now
        )
      end

      def namespace_for(metric)
        metric.group.to_s.split("_").map(&:capitalize).join
      end

      def unit_for(metric)
        UNIT_MAP.fetch(metric.unit&.to_sym, "None")
      end

      def dimensions_for(tags)
        tag_dimensions = tags.to_h.map { |name, value| {name: name.to_s, value: value.to_s} }
        tag_dimensions + Config.instance.dimensions.map { |name, value| {name: name.to_s, value: value.to_s} }
      end
    end
  end
end
