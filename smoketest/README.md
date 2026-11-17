# Speedshop::Cloudwatch Smoketest

This directory contains several Rails 8 integration smoke tests that capture CloudWatch API calls with WebMock:

- `./run_smoketest.sh` exercises the built-in Puma, Rack, Sidekiq, Solid Queue, and ActiveJob integrations.
- `./run_yabeda_parity_smoketest.sh` exercises the Yabeda adapter through a parity layer that mirrors the built-in metric contract as closely as practical.
- `./run_yabeda_stock_plugin_smoketest.sh` exercises the stock Yabeda plugin path with `yabeda-puma-plugin`, `yabeda-sidekiq`, and `yabeda-rack-queue`.

All scripts start Redis, Puma (2 workers), Sidekiq, and Solid Queue, generate traffic, wait for async flushes, and then verify the captured metrics. Requires Ruby 3.4.7 and Redis.

Set `SOLID_QUEUE_SUPERVISOR_MODE` to `fork` (default) or `async` to choose how the Solid Queue supervisor starts. Set `SOLID_QUEUE_IN_PUMA=true` to start it with the Puma plugin.
