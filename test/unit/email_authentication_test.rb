require_relative '../test_helper'

class EmailAuthenticationTest < ActiveSupport::TestCase
  include OutOfBandAuthTestHelpers

  def setup
    @user = User.find(2)
    AuthSourceOutOfBand.delete_all
    ActionMailer::Base.deliveries.clear
    @scheme = OutOfBandAuth::Email.new(@user)
  end

  def test_code_is_hashed_and_single_use
    assert @scheme.send_code
    code = emailed_code
    challenge = AuthSourceOutOfBand.find_by!(user_id: @user.id)
    assert_match(/\A[0-9]{6}\z/, code)
    assert_not_equal code, challenge.code_digest
    assert_equal 64, challenge.code_digest.length
    assert_not challenge.has_attribute?(:verification_code)
    assert @scheme.verify_otp!(code)
    assert_not @scheme.verify_otp!(code)
  end

  def test_code_expires
    @scheme.send_code
    code = emailed_code
    travel 121.seconds do
      assert_not @scheme.verify_otp!(code)
    end
  end

  def test_attempt_limit_includes_malformed_input_and_survives_resend
    @scheme.send_code
    code = emailed_code
    3.times { assert_not @scheme.verify_otp!('invalid') }
    travel 31.seconds do
      assert_no_difference('ActionMailer::Base.deliveries.size') { @scheme.send_code }
      assert_not @scheme.verify_otp!(code)
    end
    travel 121.seconds do
      @scheme.send_code
      assert @scheme.verify_otp!(emailed_code)
    end
  end

  def test_resend_throttles_email_and_invalidates_old_code
    @scheme.send_code
    old_code = emailed_code
    assert_no_difference('ActionMailer::Base.deliveries.size') { @scheme.send_code }
    travel 31.seconds do
      # Deterministic replacement prevents a one-in-a-million flaky assertion.
      SecureRandom.stubs(:random_number).with(1_000_000).returns((old_code.to_i + 1) % 1_000_000)
      assert_difference('ActionMailer::Base.deliveries.size', 1) { @scheme.send_code }
      assert_not @scheme.verify_otp!(old_code)
      assert @scheme.verify_otp!(emailed_code)
    end
  end

  def test_code_is_bound_to_recipient
    @scheme.send_code
    assert_not OutOfBandAuth::Email.new(User.find(3)).verify_otp!(emailed_code)
  end

  def test_failed_delivery_does_not_leave_a_valid_challenge
    delivery = mock
    delivery.expects(:deliver_now).raises(IOError)
    OutOfBandAuthMailer.expects(:verification_code).returns(delivery)
    assert_raises(IOError) { @scheme.send_code }
    assert_nil AuthSourceOutOfBand.find_by!(user_id: @user.id).code_digest
  end

  def test_native_backup_code_is_single_use
    @user.update!(twofa_scheme: 'email')
    code = @scheme.init_backup_codes!.first.value
    assert @scheme.verify!(code)
    assert_not @scheme.verify!(code)
  end

  def test_registration_is_idempotent_and_keeps_totp
    2.times { OutOfBandAuth.prepare }
    assert_equal OutOfBandAuth::Email, Redmine::Twofa.for_twofa_scheme('email')
    assert_equal Redmine::Twofa::Totp, Redmine::Twofa.for_twofa_scheme('totp')
    assert_equal 1, Redmine::Twofa.available_schemes.count('email')
  end
end
