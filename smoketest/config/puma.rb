require_relative "../config/environment"

max_threads_count = ENV.fetch("RAILS_MAX_THREADS", 5)
min_threads_count = ENV.fetch("RAILS_MIN_THREADS") { max_threads_count }
threads min_threads_count, max_threads_count

port ENV.fetch("PORT", 3000)
environment ENV.fetch("RAILS_ENV", "development")
pidfile ENV.fetch("PIDFILE", "tmp/pids/server.pid")

workers ENV.fetch("WEB_CONCURRENCY", 2)
preload_app!

case ENV["SMOKETEST_MODE"]
when "yabeda_plugin"
  activate_control_app
  plugin :yabeda
when "yabeda_parity"
  # The parity smoketest uses custom Yabeda collectors that mirror the built-in contract.
else
  Speedshop::Cloudwatch.configure do |config|
    config.collectors << :puma
  end
end

on_booted do
  Speedshop::Cloudwatch.start!
end
