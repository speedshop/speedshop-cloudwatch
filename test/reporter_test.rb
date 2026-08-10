# frozen_string_literal: true

require "test_helper"

class ReporterTest < SpeedshopCloudwatchTest
  def setup
    super
    @config = Speedshop::Cloudwatch.config
    @config.interval = 60
    @config.metrics[:sidekiq] = [:EnqueuedJobs, :ProcessedJobs, :FailedJobs, :QueueLatency, :QueueSize]
    @reporter = Speedshop::Cloudwatch.reporter
    @metric_mapper = Speedshop::Cloudwatch.metric_mapper
  end

  def teardown
    @reporter&.stop!
    super
  end

  def test_queues_metrics
    @metric_mapper.report(metric: :EnqueuedJobs, value: 42, integration: :sidekiq)
    @metric_mapper.report(metric: :ProcessedJobs, value: 100, integration: :sidekiq)
  end

  def test_can_start_and_stop
    @reporter.start!
    @reporter.stop!
  end

  def test_respects_puma_metrics_whitelist
    @config.metrics[:puma] = [:Workers]
    @metric_mapper.report(metric: :Workers, value: 4)
    @metric_mapper.report(metric: :BootedWorkers, value: 4)
    @reporter.start!
    @reporter.flush_now!

    metrics = @test_client.find_metrics
    assert_equal 1, metrics.size
    assert_equal "Workers", metrics.first[:metric_name]
  end

  def test_respects_sidekiq_metrics_whitelist
    @config.metrics[:sidekiq] = [:EnqueuedJobs, :QueueLatency]
    @metric_mapper.report(metric: :EnqueuedJobs, value: 10)
    @metric_mapper.report(metric: :ProcessedJobs, value: 100)
    @metric_mapper.report(metric: :QueueLatency, value: 5.2)
    @reporter.start!
    @reporter.flush_now!

    metrics = @test_client.find_metrics
    assert_equal 2, metrics.size
    metric_names = metrics.map { |m| m[:metric_name] }
    assert_includes metric_names, "EnqueuedJobs"
    assert_includes metric_names, "QueueLatency"
    refute_includes metric_names, "ProcessedJobs"
  end

  def test_started_returns_false_when_not_started
    refute @reporter.started?
  end

  def test_started_returns_true_when_started
    @reporter.start!
    assert @reporter.started?
  end

  def test_started_returns_false_after_stop
    @reporter.start!
    @reporter.stop!
    refute @reporter.started?
  end

  def test_start_is_idempotent
    @reporter.start!
    @reporter.start!
    sleep(0.01)
    assert_equal 1, Thread.list.count { |t| t.name == "scw_reporter" }
  end

  def test_started_detects_dead_thread
    @reporter.start!
    sleep(0.01)
    thread = Thread.list.find { |t| t.name == "scw_reporter" }
    thread.kill && thread.join

    refute @reporter.started?
  end

  def test_adds_custom_dimensions_to_metrics
    @config.dimensions = {ServiceName: "myservice-api", Environment: "production"}
    @metric_mapper.report(metric: :EnqueuedJobs, value: 42, dimensions: {Region: "us-east-1"}, integration: :sidekiq)
    @reporter.start!
    @reporter.flush_now!

    metrics = @test_client.find_metrics
    assert_equal 1, metrics.size
    dimensions = metrics.first[:dimensions]
    assert_equal 3, dimensions.size

    dimension_names = dimensions.map { |d| d[:name] }
    assert_includes dimension_names, "Region"
    assert_includes dimension_names, "ServiceName"
    assert_includes dimension_names, "Environment"

    service_dim = dimensions.find { |d| d[:name] == "ServiceName" }
    assert_equal "myservice-api", service_dim[:value]

    env_dim = dimensions.find { |d| d[:name] == "Environment" }
    assert_equal "production", env_dim[:value]
  end

  def test_works_without_custom_dimensions
    @metric_mapper.report(metric: :EnqueuedJobs, value: 42, dimensions: {Region: "us-east-1"}, integration: :sidekiq)
    @reporter.start!
    @reporter.flush_now!

    metrics = @test_client.find_metrics
    assert_equal 1, metrics.size
    dimensions = metrics.first[:dimensions]
    assert_equal 1, dimensions.size
    assert_equal "Region", dimensions.first[:name]
    assert_equal "us-east-1", dimensions.first[:value]
  end

  def test_custom_dimensions_with_no_metric_dimensions
    @config.dimensions = {ServiceName: "myservice-api"}
    @metric_mapper.report(metric: :EnqueuedJobs, value: 42, integration: :sidekiq)
    @reporter.start!
    @reporter.flush_now!

    metrics = @test_client.find_metrics
    assert_equal 1, metrics.size
    dimensions = metrics.first[:dimensions]
    assert_equal 1, dimensions.size
    assert_equal "ServiceName", dimensions.first[:name]
    assert_equal "myservice-api", dimensions.first[:value]
  end

  def test_lazy_startup_on_first_report
    refute @reporter.started?

    @metric_mapper.report(metric: :EnqueuedJobs, value: 42, integration: :sidekiq)

    assert @reporter.started?
  end

  def test_lazy_startup_restarts_after_stop
    @metric_mapper.report(metric: :EnqueuedJobs, value: 1, integration: :sidekiq)
    assert @reporter.started?

    @reporter.stop!
    refute @reporter.started?

    @metric_mapper.report(metric: :ProcessedJobs, value: 2, integration: :sidekiq)
    assert @reporter.started?
  end

  def test_does_not_start_in_disabled_environment
    @config.enabled_environments = ["production"]
    @config.environment = "development"

    @reporter.start!

    refute @reporter.started?
  end

  def test_starts_in_enabled_environment
    @config.enabled_environments = ["production", "staging"]
    @config.environment = "staging"

    @reporter.start!

    assert @reporter.started?
  end

  def test_does_not_start_on_report_in_disabled_environment
    @config.enabled_environments = ["production"]
    @config.environment = "test"

    @metric_mapper.report(metric: :EnqueuedJobs, value: 42, integration: :sidekiq)

    refute @reporter.started?
    assert_equal 0, @test_client.metric_count
  end

  def test_starts_on_report_in_enabled_environment
    @config.enabled_environments = ["development", "test"]
    @config.environment = "test"

    @metric_mapper.report(metric: :EnqueuedJobs, value: 42, integration: :sidekiq)

    assert @reporter.started?
  end

  def test_queue_respects_max_size
    @config.queue_max_size = 5

    6.times { |i| @metric_mapper.report(metric: :EnqueuedJobs, integration: :sidekiq, value: i) }
    @reporter.start!
    @reporter.flush_now!

    metrics = @test_client.find_metrics(metric_name: :EnqueuedJobs)
    assert_equal 1, metrics.size

    metric = metrics.first
    assert_equal [1.0, 2.0, 3.0, 4.0, 5.0], metric[:values]
    assert_equal [1, 1, 1, 1, 1], metric[:counts]
  end

  def test_queue_drops_oldest_metrics_on_overflow
    @config.queue_max_size = 3

    @metric_mapper.report(metric: :EnqueuedJobs, integration: :sidekiq, value: 1)
    @metric_mapper.report(metric: :EnqueuedJobs, integration: :sidekiq, value: 2)
    @metric_mapper.report(metric: :EnqueuedJobs, integration: :sidekiq, value: 3)
    @metric_mapper.report(metric: :EnqueuedJobs, integration: :sidekiq, value: 4)
    @reporter.start!
    @reporter.flush_now!

    metrics = @test_client.find_metrics(metric_name: :EnqueuedJobs)
    assert_equal 1, metrics.size

    metric = metrics.first
    assert_equal [2.0, 3.0, 4.0], metric[:values]
    assert_equal [1, 1, 1], metric[:counts]
  end

  def test_aggregates_repeated_values_as_values_and_counts
    [10, 10, 10, 25, 100].each do |value|
      @metric_mapper.report(metric: :EnqueuedJobs, integration: :sidekiq, value: value)
    end
    @reporter.start!
    @reporter.flush_now!

    metric = @test_client.find_metrics(metric_name: :EnqueuedJobs).first
    assert_equal [10.0, 25.0, 100.0], metric[:values]
    assert_equal [3, 1, 1], metric[:counts]
    refute metric.key?(:statistic_values)
  end

  def test_preserves_explicit_statistic_values
    [
      {sample_count: 2, sum: 30, minimum: 10, maximum: 20},
      {sample_count: 3, sum: 120, minimum: 30, maximum: 50}
    ].each do |statistic_values|
      @metric_mapper.report(metric: :EnqueuedJobs, integration: :sidekiq, statistic_values: statistic_values)
    end
    @reporter.start!
    @reporter.flush_now!

    metric = @test_client.find_metrics(metric_name: :EnqueuedJobs).first
    assert_equal({sample_count: 5.0, sum: 150.0, minimum: 10.0, maximum: 50.0}, metric[:statistic_values])
  end

  def test_splits_distributions_at_cloudwatch_value_limit
    151.times do |value|
      @metric_mapper.report(metric: :EnqueuedJobs, integration: :sidekiq, value: value)
    end
    @reporter.start!
    @reporter.flush_now!

    metrics = @test_client.find_metrics(metric_name: :EnqueuedJobs)
    assert_equal 2, metrics.size
    assert_equal [150, 1], metrics.map { |metric| metric[:values].size }
    assert_equal 151, metrics.sum { |metric| metric[:counts].sum }
  end

  def test_groups_observations_by_reporting_period
    @config.interval = 60
    enqueue_at(value: 10, timestamp: Time.utc(2026, 8, 10, 12, 0, 58))
    enqueue_at(value: 15, timestamp: Time.utc(2026, 8, 10, 12, 0, 59))
    enqueue_at(value: 20, timestamp: Time.utc(2026, 8, 10, 12, 1, 0))
    @reporter.start!
    @reporter.flush_now!

    metrics = @test_client.find_metrics(metric_name: :EnqueuedJobs)
    assert_equal 2, metrics.size
    assert_equal [Time.utc(2026, 8, 10, 12, 0, 0), Time.utc(2026, 8, 10, 12, 1, 0)], metrics.map { |metric| metric[:timestamp] }
    assert_equal [10.0, 15.0], metrics.first[:values]
  end

  def test_overflow_logging_is_throttled
    @config.queue_max_size = 2
    log_output = StringIO.new
    @config.logger = Logger.new(log_output)

    5.times { |i| @metric_mapper.report(metric: :EnqueuedJobs, integration: :sidekiq, value: i) }

    @reporter.send(:log_overflow_if_needed)

    log_content = log_output.string
    assert_match(/dropped 3 oldest metric/, log_content)
    assert_match(/max queue size: 2/, log_content)
  end

  def test_overflow_counter_resets_after_logging
    @config.queue_max_size = 2
    @config.logger = Logger.new(nil)

    5.times { |i| @metric_mapper.report(metric: :EnqueuedJobs, integration: :sidekiq, value: i) }
    @reporter.send(:log_overflow_if_needed)

    log_output = StringIO.new
    @config.logger = Logger.new(log_output)

    @reporter.send(:log_overflow_if_needed)

    assert_empty log_output.string
  end

  private

  def enqueue_at(value:, timestamp:)
    @reporter.enqueue(
      metric_name: "EnqueuedJobs",
      namespace: "Sidekiq",
      unit: "Count",
      dimensions: [],
      value: value,
      timestamp: timestamp
    )
  end
end
