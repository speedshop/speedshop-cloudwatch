require "aws-sdk-cloudwatch"
require "csv"
require "webmock"

include WebMock::API

WebMock.enable!
WebMock.disable_net_connect!(allow_localhost: true)

CAPTURED_METRICS_FILE = ENV.fetch("CAPTURED_METRICS_FILE", "captured_metrics.csv")
METRICS_FILE = Rails.root.join("tmp", CAPTURED_METRICS_FILE)

FileUtils.mkdir_p(METRICS_FILE.dirname)

unless File.exist?(METRICS_FILE)
  CSV.open(METRICS_FILE, "w") do |csv|
    csv << ["timestamp", "body", "headers"]
  end
end

WebMock.stub_request(:post, /monitoring\..*\.amazonaws\.com/)
  .to_return do |request|
    CSV.open(METRICS_FILE, "a") do |csv|
      csv << [Time.now.to_s, request.body, request.headers.to_json]
    end

    {status: 200, body: '<?xml version="1.0"?><PutMetricDataResponse xmlns="http://monitoring.amazonaws.com/doc/2010-08-01/"><ResponseMetadata><RequestId>test-request-id</RequestId></ResponseMetadata></PutMetricDataResponse>', headers: {"Content-Type" => "text/xml", "Content-Encoding" => "identity"}}
  end

Speedshop::Cloudwatch.configure do |config|
  config.client = Aws::CloudWatch::Client.new(
    region: "us-east-1",
    credentials: Aws::Credentials.new("fake-key", "fake-secret")
  )
  config.interval = 15
  config.logger = Rails.logger

  if ENV["SMOKETEST_MODE"] == "builtin"
    # Enable all built-in metrics for smoketest
    config.metrics[:puma] = [
      :Workers, :BootedWorkers, :OldWorkers, :Running, :Backlog, :PoolCapacity, :MaxThreads
    ]
    config.metrics[:sidekiq] = [
      :EnqueuedJobs, :ProcessedJobs, :FailedJobs, :ScheduledJobs, :RetryJobs,
      :DeadJobs, :Workers, :Processes, :DefaultQueueLatency, :Capacity,
      :Utilization, :QueueLatency, :QueueSize
    ]
    config.metrics[:rack] = [:RequestQueueTime]
    config.metrics[:active_job] = [:QueueLatency]
  else
    config.metrics[:puma] = []
    config.metrics[:sidekiq] = []
    config.metrics[:rack] = []
    config.metrics[:active_job] = []
  end

  config.environment = "production"
end
