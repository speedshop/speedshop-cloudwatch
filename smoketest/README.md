# Speedshop::Cloudwatch Smoketest

This directory contains two Rails 8 integration smoke tests that capture CloudWatch API calls with WebMock:

- `./run_smoketest.sh` exercises the built-in Puma, Rack, Sidekiq, and ActiveJob integrations.
- `./run_yabeda_smoketest.sh` exercises the Yabeda adapter with `yabeda-puma-plugin`, `yabeda-sidekiq`, and `yabeda-rack-queue`.

Both scripts start Redis, Puma (2 workers), and Sidekiq, generate traffic, wait for async flushes, and then verify the captured metrics. Requires Ruby 3.4.7 and Redis.
