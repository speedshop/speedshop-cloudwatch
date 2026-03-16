# frozen_string_literal: true

require "test_helper"
require "speedshop/cloudwatch/yabeda"
require "yabeda"

class YabedaTest < SpeedshopCloudwatchTest
  def setup
    super
    verbose = $VERBOSE
    $VERBOSE = nil
    Yabeda.reset!
    configure_yabeda
    $VERBOSE = verbose
    @reporter = Speedshop::Cloudwatch.reporter
  end

  def teardown
    verbose = $VERBOSE
    $VERBOSE = nil
    Yabeda.reset!
    $VERBOSE = verbose
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
end
