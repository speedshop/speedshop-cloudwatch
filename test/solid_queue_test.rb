# frozen_string_literal: true

require "test_helper"

class SolidQueueTest < SpeedshopCloudwatchTest
  def setup
    super
    skip "Solid Queue is not installed; skipping Solid Queue tests" unless solid_queue_installed?
    require_relative "support/solid_queue_database"
    ActiveRecord::Base.connection.begin_transaction(joinable: false)
    require "speedshop/cloudwatch/solid_queue"
  end

  def teardown
    Speedshop::Cloudwatch::SolidQueue.supervisor = nil
    ActiveRecord::Base.connection.rollback_transaction if solid_queue_installed?
    super
  end

  def test_filters_queues_when_configured
    enqueue_test_jobs
    Speedshop::Cloudwatch.configure do |config|
      config.solid_queue_queues = ["critical", "default"]
    end

    queue_names = collect_solid_queue_queue_names
    assert_includes queue_names, "critical"
    assert_includes queue_names, "default"
    refute_includes queue_names, "low_priority"
  end

  def test_monitors_all_queues_by_default
    enqueue_test_jobs
    Speedshop::Cloudwatch.configure { |config| config.solid_queue_queues = nil }

    queue_names = collect_solid_queue_queue_names
    assert_includes queue_names, "critical"
    assert_includes queue_names, "default"
    assert_includes queue_names, "low_priority"
  end

  def test_reports_queue_latency_per_queue
    supervisor = start_supervisor
    enqueue_test_job("critical", created_at: 120.seconds.ago)
    enqueue_test_job("default", created_at: 240.seconds.ago)

    collect_solid_queue_metrics(supervisor)

    values = queue_metric_values("QueueLatency")
    assert_in_delta 120, values.fetch("critical"), 1
    assert_in_delta 240, values.fetch("default"), 1
  end

  def test_reports_queue_size_per_queue
    supervisor = start_supervisor
    enqueue_test_jobs("critical" => 2, "default" => 1)
    enqueue_test_job("low_priority", scheduled_at: 1.hour.from_now)

    collect_solid_queue_metrics(supervisor)

    values = queue_metric_values("QueueSize")
    assert_equal 2, values.fetch("critical")
    assert_equal 1, values.fetch("default")
    assert_equal 0, values.fetch("low_priority")
  end

  def test_reports_processes
    supervisor = start_supervisor
    2.times { start_worker(supervisor_id: supervisor.process_id) }

    collect_solid_queue_metrics(supervisor)

    assert_equal 2, @test_client.find_metrics(metric_name: "Processes").first[:value]
  end

  def test_reports_workers
    supervisor = start_supervisor
    first_worker = start_worker(supervisor_id: supervisor.process_id)
    second_worker = start_worker(supervisor_id: supervisor.process_id)
    create_and_assign_jobs(first_worker, 1)
    create_and_assign_jobs(second_worker, 2)

    collect_solid_queue_metrics(supervisor)

    assert_equal 3, @test_client.find_metrics(metric_name: "Workers").first[:value]
  end

  def test_reports_capacity
    supervisor = start_supervisor
    start_worker(supervisor_id: supervisor.process_id, pool_size: 2)
    start_worker(supervisor_id: supervisor.process_id, pool_size: 4)

    collect_solid_queue_metrics(supervisor)

    assert_equal 6, @test_client.find_metrics(metric_name: "Capacity").first[:value]
  end

  def test_reports_utilization
    supervisor = start_supervisor
    busy_worker = start_worker(supervisor_id: supervisor.process_id, pool_size: 2)
    start_worker(supervisor_id: supervisor.process_id, pool_size: 4)
    create_and_assign_jobs(busy_worker, 1)

    collect_solid_queue_metrics(supervisor)

    assert_in_delta 25.0, @test_client.find_metrics(metric_name: "Utilization").first[:value], 0.01
  end

  def test_counts_only_its_own_supervisors_workers
    supervisor = start_supervisor
    other_supervisor = start_supervisor
    start_worker(supervisor_id: supervisor.process_id, pool_size: 3)
    start_worker(supervisor_id: other_supervisor.process_id, pool_size: 5)

    collect_solid_queue_metrics(supervisor)

    assert_equal 1, @test_client.find_metrics(metric_name: "Processes").first[:value]
    assert_equal 3, @test_client.find_metrics(metric_name: "Capacity").first[:value]
  end

  def test_ignores_stale_workers
    supervisor = start_supervisor
    start_worker(supervisor_id: supervisor.process_id, pool_size: 3)
    start_worker(
      supervisor_id: supervisor.process_id,
      pool_size: 5,
      last_heartbeat_at: ::SolidQueue.process_alive_threshold.ago - 60
    )

    collect_solid_queue_metrics(supervisor)

    assert_equal 1, @test_client.find_metrics(metric_name: "Processes").first[:value]
    assert_equal 3, @test_client.find_metrics(metric_name: "Capacity").first[:value]
  end

  def test_reports_no_process_metrics_without_live_workers
    collect_solid_queue_metrics(start_supervisor)

    assert_empty @test_client.find_metrics(metric_name: "Processes")
  end

  def test_skips_collecting_in_a_forked_process
    supervisor = start_supervisor
    start_worker(supervisor_id: supervisor.process_id)

    ::Process.stub(:pid, supervisor.pid + 1) do
      collect_solid_queue_metrics(supervisor)
    end

    assert_empty @test_client.find_metrics
  end

  def test_logs_error_when_collection_fails
    supervisor = start_supervisor
    logger = TestDoubles::LoggerDouble.new
    Speedshop::Cloudwatch.configure { |config| config.logger = logger }

    ::SolidQueue::Process.stub(:where, ->(*) { raise "boom" }) do
      collect_solid_queue_metrics(supervisor)
    end

    assert logger.error_logged?("Failed to collect Solid Queue metrics"), "Expected error to be logged"
  end

  private

  def solid_queue_installed?
    Gem.loaded_specs.key?("solid_queue")
  end

  def start_supervisor
    row = ::SolidQueue::Process.create!(
      kind: "Supervisor",
      name: "supervisor-#{SecureRandom.hex(4)}",
      pid: ::Process.pid,
      last_heartbeat_at: Time.now
    )
    Struct.new(:pid, :process_id).new(row.pid, row.id)
  end

  def start_worker(supervisor_id:, pool_size: 3, last_heartbeat_at: Time.now)
    ::SolidQueue::Process.create!(
      kind: "Worker",
      name: "worker-#{SecureRandom.hex(4)}",
      pid: ::Process.pid,
      supervisor_id: supervisor_id,
      last_heartbeat_at: last_heartbeat_at,
      metadata: {pool_size: pool_size}
    )
  end

  def create_and_assign_jobs(worker, count)
    count.times do
      ::SolidQueue::Job.create!(queue_name: "default", class_name: "TestJob")
    end
    ::SolidQueue::ReadyExecution.claim(["*"], count, worker.id)
  end

  def enqueue_test_jobs(queue_counts = {"critical" => 1, "default" => 1, "low_priority" => 1})
    queue_counts.each do |queue_name, count|
      count.times { enqueue_test_job(queue_name) }
    end
  end

  def enqueue_test_job(queue_name, created_at: nil, scheduled_at: nil)
    job = ::SolidQueue::Job.create!(queue_name: queue_name, class_name: "TestJob", scheduled_at: scheduled_at)
    job.ready_execution.update!(created_at: created_at) if created_at
    job
  end

  def collect_solid_queue_metrics(supervisor)
    Speedshop::Cloudwatch.configure do |config|
      config.metrics[:solid_queue] = [:Processes, :Workers, :Capacity, :Utilization, :QueueLatency, :QueueSize]
    end
    Speedshop::Cloudwatch::SolidQueue.supervisor = supervisor
    Speedshop::Cloudwatch::SolidQueue.new.collect

    reporter = Speedshop::Cloudwatch.reporter
    reporter.start!
    reporter.flush_now!
  end

  def queue_metric_values(metric_name)
    @test_client.find_metrics(metric_name: metric_name).each_with_object({}) do |metric, values|
      queue_name = metric[:dimensions].find { |dimension| dimension[:name] == "QueueName" }[:value]
      values[queue_name] = metric[:value]
    end
  end

  def collect_solid_queue_queue_names
    collect_solid_queue_metrics(start_supervisor)

    metrics = @test_client.find_metrics
    queue_metrics = metrics.select do |metric|
      metric[:dimensions]&.any? { |dimension| dimension[:name] == "QueueName" }
    end
    queue_metrics.map { |metric| metric[:dimensions].find { |dimension| dimension[:name] == "QueueName" }[:value] }.uniq
  end
end
