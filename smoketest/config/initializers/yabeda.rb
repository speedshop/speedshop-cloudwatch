mode = ENV["SMOKETEST_MODE"]
return unless mode == "yabeda_parity" || mode == "yabeda_plugin"

if mode == "yabeda_parity"
  require_relative "../../lib/yabeda_parity"

  Smoketest::YabedaParity.setup!
  Rails.application.config.middleware.use Smoketest::YabedaParity::RackMiddleware
else
  require "speedshop/cloudwatch/yabeda"
  require "yabeda/rack/queue"
  require "yabeda/sidekiq"

  Yabeda.register_adapter(:cloudwatch, Speedshop::Cloudwatch::Yabeda.new)

  Rails.application.config.middleware.use Yabeda::Rack::Queue::Middleware, logger: Rails.logger
end
