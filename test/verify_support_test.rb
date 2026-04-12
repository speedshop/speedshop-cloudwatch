# frozen_string_literal: true

require "csv"
require "tmpdir"
require "test_helper"
require_relative "../smoketest/verify_support"

class VerifySupportTest < SpeedshopCloudwatchTest
  def test_built_in_metrics_by_namespace_covers_all_builtin_metrics
    built_in_metrics = VerifySupport.built_in_metrics_by_namespace

    assert_includes built_in_metrics.fetch("Puma"), "OldWorkers"
    assert_includes built_in_metrics.fetch("Puma"), "Backlog"
    assert_includes built_in_metrics.fetch("Sidekiq"), "QueueSize"
    assert_includes built_in_metrics.fetch("Sidekiq"), "DefaultQueueLatency"
    assert_includes built_in_metrics.fetch("Rack"), "RequestQueueTime"
    assert_includes built_in_metrics.fetch("ActiveJob"), "QueueLatency"
  end

  def test_parses_metric_details_from_cloudwatch_query_payloads
    with_metrics_file do |metrics_file|
      verifier = VerifySupport.new(metrics_file: metrics_file)

      assert_equal ["job_runtime", "jobs_enqueued_total"], verifier.captured_metrics.fetch("Sidekiq").sort
      assert_equal ["duration"], verifier.captured_metrics.fetch("RackQueue")

      assert_equal ["None"], verifier.metric_units(namespace: "Sidekiq", metric_name: "jobs_enqueued_total")
      assert_equal ["Seconds"], verifier.metric_units(namespace: "Sidekiq", metric_name: "job_runtime")
      assert_equal %w[queue worker], verifier.metric_dimension_names(namespace: "Sidekiq", metric_name: "jobs_enqueued_total")
      assert_equal ["default"], verifier.metric_dimension_values(namespace: "Sidekiq", metric_name: "jobs_enqueued_total", dimension_name: "queue")
      assert_equal ["TestSidekiqJob"], verifier.metric_dimension_values(namespace: "Sidekiq", metric_name: "jobs_enqueued_total", dimension_name: "worker")
      assert_equal [], verifier.metric_dimension_names(namespace: "RackQueue", metric_name: "duration")

      assert_equal 3.0, verifier.metric_value_sum(namespace: "Sidekiq", metric_name: "jobs_enqueued_total")
      assert_equal 2.0, verifier.metric_sample_total(namespace: "Sidekiq", metric_name: "job_runtime")
      assert_in_delta 0.25, verifier.metric_value_sum(namespace: "Sidekiq", metric_name: "job_runtime"), 0.001
      assert_equal 1.0, verifier.metric_sample_total(namespace: "RackQueue", metric_name: "duration")
    end
  end

  private

  def with_metrics_file
    Dir.mktmpdir do |dir|
      metrics_file = File.join(dir, "captured_metrics.csv")

      CSV.open(metrics_file, "w") do |csv|
        csv << ["timestamp", "body", "headers"]
        csv << [Time.now.to_s, sidekiq_request_body, "{}"]
        csv << [Time.now.to_s, rack_queue_request_body, "{}"]
      end

      yield metrics_file
    end
  end

  def sidekiq_request_body
    [
      "Namespace=MyApp%2FSidekiq",
      "MetricData.member.1.MetricName=jobs_enqueued_total",
      "MetricData.member.1.Unit=None",
      "MetricData.member.1.Value=3",
      "MetricData.member.1.Dimensions.member.1.Name=queue",
      "MetricData.member.1.Dimensions.member.1.Value=default",
      "MetricData.member.1.Dimensions.member.2.Name=worker",
      "MetricData.member.1.Dimensions.member.2.Value=TestSidekiqJob",
      "MetricData.member.2.MetricName=job_runtime",
      "MetricData.member.2.Unit=Seconds",
      "MetricData.member.2.StatisticValues.SampleCount=2",
      "MetricData.member.2.StatisticValues.Sum=0.25",
      "MetricData.member.2.StatisticValues.Minimum=0.1",
      "MetricData.member.2.StatisticValues.Maximum=0.15",
      "MetricData.member.2.Dimensions.member.1.Name=queue",
      "MetricData.member.2.Dimensions.member.1.Value=default",
      "MetricData.member.2.Dimensions.member.2.Name=worker",
      "MetricData.member.2.Dimensions.member.2.Value=TestSidekiqJob"
    ].join("&")
  end

  def rack_queue_request_body
    [
      "Namespace=RackQueue",
      "MetricData.member.1.MetricName=duration",
      "MetricData.member.1.Unit=Seconds",
      "MetricData.member.1.Value=0.01"
    ].join("&")
  end
end
