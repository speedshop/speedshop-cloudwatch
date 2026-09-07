module SmoketestMetricContract
  module_function

  def expected_metrics
    {
      "Puma" => %w[Workers BootedWorkers OldWorkers Running Backlog PoolCapacity MaxThreads],
      "Rack" => %w[RequestQueueTime],
      "ActiveJob" => %w[QueueLatency],
      "Sidekiq" => %w[
        EnqueuedJobs
        ProcessedJobs
        FailedJobs
        ScheduledJobs
        RetryJobs
        DeadJobs
        Workers
        Processes
        DefaultQueueLatency
        Capacity
        Utilization
        QueueLatency
        QueueSize
      ]
    }
  end

  def forbidden_metrics
    {"Test" => ["RakeTaskMetric"]}
  end

  def expected_unique_metric_counts
    {
      "Puma" => 7,
      "Rack" => 1,
      "ActiveJob" => 1,
      "Sidekiq" => 13
    }
  end

  def expected_metric_counts
    {
      "Puma" => {
        "Workers" => 1,
        "Running" => 1,
        "Backlog" => 1,
        "PoolCapacity" => 1,
        "MaxThreads" => 1
      },
      "Rack" => {"RequestQueueTime" => 1},
      "ActiveJob" => {"QueueLatency" => 1},
      "Sidekiq" => {
        "EnqueuedJobs" => 1,
        "QueueLatency" => 1,
        "QueueSize" => 1
      }
    }
  end

  def expected_units
    {
      "Puma" => {
        "Workers" => ["Count"],
        "BootedWorkers" => ["Count"],
        "OldWorkers" => ["Count"],
        "Running" => ["Count"],
        "Backlog" => ["Count"],
        "PoolCapacity" => ["Count"],
        "MaxThreads" => ["Count"]
      },
      "Rack" => {
        "RequestQueueTime" => ["Milliseconds"]
      },
      "ActiveJob" => {
        "QueueLatency" => ["Seconds"]
      },
      "Sidekiq" => {
        "EnqueuedJobs" => ["Count"],
        "ProcessedJobs" => ["Count"],
        "FailedJobs" => ["Count"],
        "ScheduledJobs" => ["Count"],
        "RetryJobs" => ["Count"],
        "DeadJobs" => ["Count"],
        "Workers" => ["Count"],
        "Processes" => ["Count"],
        "DefaultQueueLatency" => ["Seconds"],
        "Capacity" => ["Count"],
        "Utilization" => ["Percent"],
        "QueueLatency" => ["Seconds"],
        "QueueSize" => ["Count"]
      }
    }
  end

  def expected_dimensions
    {
      "Puma" => {
        "Workers" => [],
        "BootedWorkers" => [],
        "OldWorkers" => [],
        "Running" => [],
        "Backlog" => [],
        "PoolCapacity" => [],
        "MaxThreads" => []
      },
      "Rack" => {
        "RequestQueueTime" => []
      },
      "ActiveJob" => {
        "QueueLatency" => %w[QueueName]
      },
      "Sidekiq" => {
        "EnqueuedJobs" => [],
        "ProcessedJobs" => [],
        "FailedJobs" => [],
        "ScheduledJobs" => [],
        "RetryJobs" => [],
        "DeadJobs" => [],
        "Workers" => [],
        "Processes" => [],
        "DefaultQueueLatency" => [],
        "Capacity" => [],
        "Utilization" => [],
        "QueueLatency" => %w[QueueName],
        "QueueSize" => %w[QueueName]
      }
    }
  end

  # A reporting bucket with one observation uses Value; repeated observations use Values/Counts.
  def allowed_value_kinds
    {
      "Puma" => {
        "Workers" => ["value"],
        "BootedWorkers" => ["value"],
        "OldWorkers" => ["value"],
        "Running" => %w[value values_counts],
        "Backlog" => %w[value values_counts],
        "PoolCapacity" => %w[value values_counts],
        "MaxThreads" => %w[value values_counts]
      },
      "Rack" => {
        "RequestQueueTime" => %w[value values_counts]
      },
      "ActiveJob" => {
        "QueueLatency" => %w[value values_counts]
      },
      "Sidekiq" => {
        "EnqueuedJobs" => ["value"],
        "ProcessedJobs" => ["value"],
        "FailedJobs" => ["value"],
        "ScheduledJobs" => ["value"],
        "RetryJobs" => ["value"],
        "DeadJobs" => ["value"],
        "Workers" => ["value"],
        "Processes" => ["value"],
        "DefaultQueueLatency" => ["value"],
        "Capacity" => ["value"],
        "Utilization" => ["value"],
        "QueueLatency" => ["value"],
        "QueueSize" => ["value"]
      }
    }
  end

  def expected_sample_totals
    {
      "Puma" => {
        "Running" => 2,
        "Backlog" => 2,
        "PoolCapacity" => 2,
        "MaxThreads" => 2
      },
      "Rack" => {
        "RequestQueueTime" => 20
      },
      "ActiveJob" => {
        "QueueLatency" => 10
      }
    }
  end
end
