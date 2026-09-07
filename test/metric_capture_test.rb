# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require_relative "../smoketest/metric_capture"
require_relative "../smoketest/verify_support"

class MetricCaptureTest < SpeedshopCloudwatchTest
  def test_captures_gzip_execution_metrics_from_sdk
    assert_sdk_capture(compressed: true)
  end

  def test_captures_uncompressed_execution_metrics_from_sdk
    assert_sdk_capture(compressed: false)
  end

  private

  def assert_sdk_capture(compressed:)
    Dir.mktmpdir do |dir|
      file = File.join(dir, "captured_metrics.csv")
      CSV.open(file, "w") { |csv| csv << %w[timestamp body headers] }
      stub_request(:post, /monitoring\..*\.amazonaws\.com/).to_return do |request|
        assert_equal compressed, request.headers["Content-Encoding"] == "gzip"
        MetricCapture.append(file, request)
        {status: 200, body: "<PutMetricDataResponse/>"}
      end
      client = Aws::CloudWatch::Client.new(region: "us-east-1", credentials: Aws::Credentials.new("fake-key", "fake-secret"),
        disable_request_compression: !compressed, request_min_compression_size_bytes: 0)
      client.put_metric_data(namespace: "Sidekiq", metric_data: [{metric_name: "jobs_executed_total", value: 20}])

      verifier = VerifySupport.new(metrics_file: file)
      assert_equal 20, verifier.metric_value_sum(namespace: "Sidekiq", metric_name: "jobs_executed_total")
    end
  end
end
