# frozen_string_literal: true

require "test_helper"

class RequestSizeTest < SpeedshopCloudwatchTest
  def test_splits_large_distribution_requests_below_uncompressed_aws_limit
    datums = Array.new(20) { |index| distribution.merge(metric_name: "Metric#{index}") }
    assert_operator serialized_size(datums), :>, Speedshop::Cloudwatch::RequestSize::LIMIT

    Speedshop::Cloudwatch.reporter.send(:send_batches, "SizeRepro", datums)

    assert_operator @test_client.calls.size, :>, 1
    assert_equal datums, @test_client.find_metrics
    @test_client.calls.each do |call|
      assert_operator call[:metric_data].size, :<=, 20
      assert_operator serialized_size(call[:metric_data]), :<=, Speedshop::Cloudwatch::RequestSize::LIMIT
    end
  end

  def test_splits_percent_encoded_payloads_including_namespace_overhead
    namespace = "Namespace /&=雪"
    datum = distribution
    datum[:dimensions].each { |dimension| dimension[:value] = "&=% " * 256 }
    datums = Array.new(20) { datum }
    assert_operator serialized_size(datums, namespace: namespace), :>, Speedshop::Cloudwatch::RequestSize::LIMIT

    Speedshop::Cloudwatch.reporter.send(:send_batches, namespace, datums)

    assert_equal datums, @test_client.find_metrics
    @test_client.calls.each do |call|
      assert_operator serialized_size(call[:metric_data], namespace: namespace), :<=, Speedshop::Cloudwatch::RequestSize::LIMIT
    end
  end

  def test_bound_covers_escaping_unicode_floats_timestamps_and_statistic_sets
    namespace = "Namespace /&=雪"
    datum = distribution.merge(metric_name: "Metric /&=雪", dimensions: [{name: "Dimension &", value: "雪 /&=%" * 100}])
    statistics = datum.reject { |key, _| [:values, :counts].include?(key) }
      .merge(statistic_values: {sample_count: 150, sum: 1.23e100, minimum: -1.23e-100, maximum: 1.23e100})
    datums = [datum, statistics, {metric_name: "Singleton", value: -1.23e-100}]
    bound = Speedshop::Cloudwatch::RequestSize.request_overhead(namespace) + datums.sum { |item| Speedshop::Cloudwatch::RequestSize.bound(item) }

    assert_operator serialized_size(datums, namespace: namespace), :<=, bound
  end

  def test_retains_twenty_datum_count_cap
    datums = Array.new(21) { |index| {metric_name: "Metric#{index}", value: index} }
    Speedshop::Cloudwatch.reporter.send(:send_batches, "SizeRepro", datums)

    assert_equal [20, 1], @test_client.calls.map { |call| call[:metric_data].size }
    assert_equal datums, @test_client.find_metrics
  end

  def test_logs_and_drops_individually_oversized_datum_and_continues
    log = StringIO.new
    Speedshop::Cloudwatch.config.logger = Logger.new(log)
    good = {metric_name: "Good", value: 1}
    oversized = {metric_name: "Oversized", dimensions: [{name: "Dimension", value: "&" * 400_000}], value: 1}
    assert_operator serialized_size([oversized]), :>, Speedshop::Cloudwatch::RequestSize::LIMIT

    Speedshop::Cloudwatch.reporter.send(:send_batches, "SizeRepro", [good, oversized, good])

    assert_equal [good, good], @test_client.find_metrics
    assert_match(/Dropping oversized CloudWatch datum: Oversized/, log.string)
  end

  private

  def distribution
    {
      metric_name: "Metric",
      dimensions: Array.new(30) { |index| {name: "D#{index}".ljust(255, "a"), value: "b" * 1024} },
      unit: "Seconds",
      timestamp: Time.utc(2026, 8, 10),
      values: Array.new(150) { |index| index + 0.123456789 },
      counts: [1.0] * 150
    }
  end

  def serialized_size(datums, namespace: "SizeRepro")
    client = Aws::CloudWatch::Client.new(region: "us-east-1", stub_responses: true, disable_request_compression: true)
    request = client.build_request(:put_metric_data, namespace: namespace, metric_data: datums)
    request.send_request
    request.context.http_request.body.size
  end
end
