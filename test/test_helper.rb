require File.expand_path('../../../test/test_helper', __dir__)

module OutOfBandAuthTestHelpers
  def emailed_code
    mail = ActionMailer::Base.deliveries.reverse.find { |m| m.subject.include?('Send verification code') }
    assert_not_nil mail
    mail.text_part.body.decoded[/\b[0-9]{6}\b/]
  end
end
