# frozen_string_literal: true

require "test_helper"
require "speedshop/cloudwatch/yabeda"
require "yabeda"

class YabedaTest < SpeedshopCloudwatchTest
  def setup
    super
    with_yabeda_warnings_silenced do
      Yabeda.reset!
      configure_yabeda
    end
    @reporter = Speedshop::Cloudwatch.reporter
  end

  def teardown
    with_yabeda_warnings_silenced do
      Yabeda.reset!
    end
    super
  end

  def test_all_four_metric_types_flow_end_to_end
    Yabeda.test_group.my_counter.increment({tag: "v"}, by: 5)
    Yabeda.test_group.my_gauge.set({tag: "v"}, 42)
    Yabeda.test_group.my_histogram.measure({tag: "v"}, 1.5)
    Yabeda.test_group.my_summary.observe({tag: "v"}, 2.0)

    flush_metrics

    assert_metric(metric_name: :my_counter, value: 5, unit: "Count")
    assert_metric(metric_name: :my_gauge, value: 42, unit: "None")
    assert_metric(metric_name: :my_histogram, value: 1.5, unit: "Seconds")
    assert_metric(metric_name: :my_summary, value: 2.0, unit: "Bytes")
  end

  def test_tags_become_dimensions_and_custom_dimensions_are_appended
    Speedshop::Cloudwatch.configure do |config|
      config.dimensions[:Env] = "test"
    end

    Yabeda.test_group.my_counter.increment({tag: "v"}, by: 5)

    flush_metrics

    metric = @test_client.find_metrics(metric_name: :my_counter).first
    assert_equal "v", dimension_value(metric, "tag")
    assert_equal "test", dimension_value(metric, "Env")
  end

  def test_namespace_is_derived_from_group_name
    Yabeda.sidekiq.jobs_done.increment({tag: "v"}, by: 1)

    flush_metrics

    assert @test_client.metric_sent?(:jobs_done, namespace: "Sidekiq")
  end

  def test_unknown_units_default_to_none
    Yabeda.sidekiq.jobs_done.increment({tag: "v"}, by: 1)

    flush_metrics

    metric = @test_client.find_metrics(metric_name: :jobs_done).first
    assert_equal "None", metric[:unit]
  end

  def test_metric_and_dimension_name_formatters_are_applied
    with_yabeda_warnings_silenced do
      Yabeda.reset!
    end

    adapter = Speedshop::Cloudwatch::Yabeda.new(
      metric_name_formatter: ->(name) { name.upcase },
      dimension_name_formatter: ->(name) { name.capitalize }
    )
    Yabeda.register_adapter(:cloudwatch, adapter)

    Yabeda.configure do
      group :test_group do
        counter :formatted_counter, comment: "Counter", tags: %i[tag], unit: :count
      end
    end
    Yabeda.configure!

    Yabeda.test_group.formatted_counter.increment({tag: "v"}, by: 1)

    flush_metrics

    metric = @test_client.find_metrics(metric_name: "FORMATTED_COUNTER").first
    refute_nil metric
    assert_equal "v", dimension_value(metric, "Tag")
  end

  def test_allowlist_filters_metrics_after_formatting
    with_yabeda_warnings_silenced do
      Yabeda.reset!
    end

    adapter = Speedshop::Cloudwatch::Yabeda.new(
      metric_name_formatter: ->(name) { name.upcase },
      allowlist: {"TestGroup" => ["ALLOWED_COUNTER"]}
    )
    Yabeda.register_adapter(:cloudwatch, adapter)

    Yabeda.configure do
      group :test_group do
        counter :allowed_counter, comment: "Counter", unit: :count
        counter :blocked_counter, comment: "Counter", unit: :count
      end
    end
    Yabeda.configure!

    Yabeda.test_group.allowed_counter.increment({}, by: 1)
    Yabeda.test_group.blocked_counter.increment({}, by: 1)

    flush_metrics

    assert @test_client.metric_sent?("ALLOWED_COUNTER", namespace: "TestGroup")
    refute @test_client.metric_sent?("BLOCKED_COUNTER", namespace: "TestGroup")
  end

  def test_multiple_updates_aggregate_through_reporter
    Yabeda.test_group.my_counter.increment({tag: "v"}, by: 5)
    Yabeda.test_group.my_counter.increment({tag: "v"}, by: 7)

    flush_metrics

    metrics = @test_client.find_metrics(metric_name: :my_counter)
    assert_equal 1, metrics.size

    statistic_values = metrics.first[:statistic_values]
    assert_equal 2.0, statistic_values[:sample_count]
    assert_equal 12.0, statistic_values[:sum]
    assert_equal 5.0, statistic_values[:minimum]
    assert_equal 7.0, statistic_values[:maximum]
  end

  def test_gauge_with_most_recent_aggregation_keeps_last_value
    Yabeda.test_group.most_recent_gauge.set({tag: "v"}, 3)
    Yabeda.test_group.most_recent_gauge.set({tag: "v"}, 10)
    Yabeda.test_group.most_recent_gauge.set({tag: "v"}, 4)

    flush_metrics

    metrics = @test_client.find_metrics(metric_name: :most_recent_gauge)
    assert_equal 1, metrics.size

    metric = metrics.first
    refute metric[:statistic_values]
    assert_equal 4, metric[:value]
    assert_equal "v", dimension_value(metric, "tag")
  end

  def test_gauge_with_max_aggregation_keeps_maximum_value
    Yabeda.test_group.max_gauge.set({tag: "v"}, 3)
    Yabeda.test_group.max_gauge.set({tag: "v"}, 10)
    Yabeda.test_group.max_gauge.set({tag: "v"}, 4)

    flush_metrics

    metrics = @test_client.find_metrics(metric_name: :max_gauge)
    assert_equal 1, metrics.size

    metric = metrics.first
    refute metric[:statistic_values]
    assert_equal 10, metric[:value]
    assert_equal "v", dimension_value(metric, "tag")
  end

  def test_first_yabeda_metric_survives_stale_reporter_pid
    fork_checks = 0

    @reporter.stub :forked?, -> {
      fork_checks += 1
      fork_checks == 1
    } do
      Yabeda.test_group.my_counter.increment({tag: "v"}, by: 5)
      @reporter.flush_now!
    end

    metric = @test_client.find_metrics(metric_name: :my_counter).first
    refute_nil metric
    assert_equal 5, metric[:value]
  end

  def test_collectors_are_run_by_reporter
    flush_metrics

    metric = @test_client.find_metrics(metric_name: :workers, namespace: "CollectorGroup").first
    refute_nil metric
    assert_equal 2, metric[:value]
  end

  def test_metrics_are_dropped_in_disabled_environments
    Speedshop::Cloudwatch.configure do |config|
      config.enabled_environments = ["production"]
      config.environment = "test"
    end

    Yabeda.test_group.my_counter.increment({tag: "v"}, by: 5)

    refute @reporter.started?
    assert_equal 0, @test_client.metric_count
  end

  private

  def configure_yabeda
    adapter = Speedshop::Cloudwatch::Yabeda.new
    Yabeda.register_adapter(:cloudwatch, adapter)

    Yabeda.configure do
      group :test_group do
        counter :my_counter, comment: "Counter", tags: %i[tag], unit: :count
        gauge :my_gauge, comment: "Gauge", tags: %i[tag], unit: :widgets
        gauge :most_recent_gauge, comment: "Most recent gauge", tags: %i[tag], aggregation: :most_recent
        gauge :max_gauge, comment: "Max gauge", tags: %i[tag], aggregation: :max
        histogram :my_histogram, comment: "Histogram", tags: %i[tag], unit: :seconds, buckets: [0.1, 1, 10]
        summary :my_summary, comment: "Summary", tags: %i[tag], unit: :bytes
      end

      group :sidekiq do
        counter :jobs_done, comment: "Jobs done", tags: %i[tag], unit: :widgets
      end

      group :collector_group do
        gauge :workers, comment: "Workers"

        collect do
          collector_group.workers.set({}, 2)
        end
      end
    end

    Yabeda.configure!
  end

  def flush_metrics
    @reporter.start!
    @reporter.flush_now!
  end

  def assert_metric(metric_name:, value:, unit:, namespace: "TestGroup")
    metric = @test_client.find_metrics(metric_name: metric_name, namespace: namespace).first
    refute_nil metric
    assert_equal value, metric[:value]
    assert_equal unit, metric[:unit]
    assert_equal "v", dimension_value(metric, "tag")
  end

  def dimension_value(metric, name)
    metric[:dimensions].find { |dimension| dimension[:name] == name }[:value]
  end

  def with_yabeda_warnings_silenced
    verbose = $VERBOSE
    # Yabeda emits noisy uninitialized instance variable warnings on Ruby 2.7
    # during reset/configure. They're harmless, but they drown out test output.
    $VERBOSE = nil
    yield
  ensure
    $VERBOSE = verbose
  end
end
