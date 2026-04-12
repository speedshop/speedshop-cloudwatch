return unless ENV["SMOKETEST_MODE"] == "yabeda"

require "speedshop/cloudwatch/yabeda"
require "yabeda/rack/queue"
require "yabeda/sidekiq"

Yabeda.register_adapter(:cloudwatch, Speedshop::Cloudwatch::Yabeda.new)

Rails.application.config.middleware.use Yabeda::Rack::Queue::Middleware, logger: Rails.logger
