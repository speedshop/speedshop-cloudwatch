# frozen_string_literal: true

require "singleton"
require_relative "metrics"

module Speedshop
  module Cloudwatch
    class MetricMapper
      include Singleton

      def report(metric:, value: nil, statistic_values: nil, dimensions: {}, integration: nil)
        return unless config.environment_enabled?

        metric_name = metric.to_sym
        resolved_integration = integration || find_integration_for_metric(metric_name)
        return unless resolved_integration
        return unless metric_allowed?(resolved_integration, metric_name)

        Reporter.instance.enqueue(build_datum(
          metric_name: metric_name,
          integration: resolved_integration,
          value: value,
          statistic_values: statistic_values,
          dimensions: dimensions
        ))
      end

      private

      def config
        Config.instance
      end

      def build_datum(metric_name:, integration:, value:, statistic_values:, dimensions:)
        metric_object = METRICS[integration]&.find { |metric| metric.name == metric_name }
        datum = {
          metric_name: metric_name.to_s,
          namespace: config.namespaces[integration],
          unit: metric_object&.unit || "None",
          dimensions: metric_dimensions(dimensions),
          timestamp: Time.now
        }

        if statistic_values
          datum[:statistic_values] = statistic_values
        else
          datum[:value] = value
        end

        datum
      end

      def metric_dimensions(dimensions)
        metric_dimensions = dimensions.map { |name, value| {name: name.to_s, value: value.to_s} }
        metric_dimensions + custom_dimensions
      end

      def metric_allowed?(integration, metric_name)
        config.metrics[integration].include?(metric_name.to_sym)
      end

      def custom_dimensions
        config.dimensions.map { |name, value| {name: name.to_s, value: value.to_s} }
      end

      def find_integration_for_metric(metric_name)
        METRICS.find { |integration, metrics| metrics.any? { |metric| metric.name == metric_name } }&.first
      end
    end
  end
end
