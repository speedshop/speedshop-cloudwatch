class TestSolidQueueJob < ActiveJob::Base
  self.queue_adapter = :solid_queue

  def perform(data)
    Rails.logger.info "TestSolidQueueJob processing: #{data}"
    sleep 0.1
  end
end
