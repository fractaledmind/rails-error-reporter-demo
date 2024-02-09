class Subscriber
  def report(error, handled:, severity:, context:, source: nil)
    Rails.logger.fatal '*' * 100
    Rails.logger.fatal 'ERROR REPORTED'
  end
end

Rails.error.subscribe(Subscriber.new)
