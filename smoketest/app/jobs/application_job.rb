require_relative "../../lib/yabeda_parity" if ENV["SMOKETEST_MODE"] == "yabeda_parity"

class ApplicationJob < ActiveJob::Base
  if ENV["SMOKETEST_MODE"] == "yabeda_parity"
    include Smoketest::YabedaParity::ActiveJob
  else
    include Speedshop::Cloudwatch::ActiveJob
  end
end
