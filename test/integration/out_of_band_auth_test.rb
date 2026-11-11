require_relative '../test_helper'

class OutOfBandAuthTest < Redmine::IntegrationTest
  include OutOfBandAuthTestHelpers

  def setup
    @user = User.find(2)
    @user.update!(twofa_scheme: 'email', must_change_passwd: false)
    AuthSourceOutOfBand.delete_all
    ActionMailer::Base.deliveries.clear
    Setting.twofa = '1'
  end

  def password_login(**extra)
    post '/login', params: { username: 'jsmith', password: 'jsmith' }.merge(extra)
    assert_redirected_to '/account/twofa/confirm'
  end

  def test_login_requires_code_before_creating_authenticated_session
    password_login
    code = emailed_code
    ['/my/page', '/my/account', '/my/api_key'].each do |path|
      get path
      assert_redirected_to %r{/login}
    end
    post '/account/twofa', params: { twofa_code: code }
    assert_redirected_to '/my/page'
    get '/my/page'
    assert_response :success
    assert_not OutOfBandAuth::Email.new(@user).verify_otp!(code)
  end

  def test_invalid_codes_never_authenticate_and_lock_the_native_session
    password_login
    3.times { post '/account/twofa', params: { twofa_code: 'invalid' } }
    assert_redirected_to '/'
    post '/account/twofa', params: { twofa_code: emailed_code }
    assert_redirected_to '/'
    get '/my/account'
    assert_redirected_to %r{/login}
  end

  def test_pending_session_expires
    password_login
    code = emailed_code
    travel 121.seconds do
      post '/account/twofa', params: { twofa_code: code }
      assert_redirected_to '/'
    end
  end

  def test_autologin_cookie_is_only_issued_after_code
    with_settings autologin: '7' do
      password_login(autologin: '1')
      assert_nil cookies['autologin']
      post '/account/twofa', params: { twofa_code: emailed_code }
      assert_redirected_to '/my/page'
      assert cookies['autologin'].present?
    end
  end

  def test_native_totp_is_unchanged_and_does_not_send_email_code
    @user.update!(twofa_scheme: 'totp', twofa_totp_key: ROTP::Base32.random)
    assert_no_difference('ActionMailer::Base.deliveries.size') { password_login }
    post '/account/twofa', params: { twofa_code: ROTP::TOTP.new(@user.twofa_totp_key).now }
    assert_redirected_to '/my/page'
    get '/my/page'
    assert_response :success
  end

  def test_password_change_is_required_after_email_confirmation
    @user.update!(must_change_passwd: true)
    password_login
    post '/account/twofa', params: { twofa_code: emailed_code }
    get '/my/page'
    assert_redirected_to '/my/password'
  end

  def test_unconfigured_user_can_login_when_twofa_optional
    @user.update!(twofa_scheme: nil)
    post '/login', params: { username: 'jsmith', password: 'jsmith' }
    assert_redirected_to '/my/page'
    get '/my/page'
    assert_response :success
  end

  def test_required_twofa_offers_both_email_and_totp
    @user.update!(twofa_scheme: nil)
    with_settings twofa: '2' do
      post '/login', params: { username: 'jsmith', password: 'jsmith' }
      get '/my/page'
      assert_redirected_to '/my/twofa/select_scheme'
      follow_redirect!
      assert_select 'input[name=scheme][value=email]'
      assert_select 'input[name=scheme][value=totp]'
    end
  end

  def test_pairing_requires_email_confirmation_and_preserves_native_settings_ui
    @user.update!(twofa_scheme: nil)
    post '/login', params: { username: 'jsmith', password: 'jsmith' }
    post '/my/twofa/email/activate/init'
    assert_redirected_to '/my/twofa/email/activate/confirm'
    follow_redirect!
    assert_response :success
    assert_nil @user.reload.twofa_scheme
    post '/my/twofa/email/activate', params: { twofa_code: emailed_code }
    assert_redirected_to '/my/account'
    assert_equal 'email', @user.reload.twofa_scheme
    get '/my/account'
    assert_response :success
  end

  def test_existing_totp_cannot_be_overwritten_by_email_pairing
    @user.update!(twofa_scheme: 'totp', twofa_totp_key: ROTP::Base32.random)
    password_login
    post '/account/twofa', params: { twofa_code: ROTP::TOTP.new(@user.twofa_totp_key).now }
    post '/my/twofa/email/activate/init'
    assert_redirected_to '/my/account'
    assert_equal 'totp', @user.reload.twofa_scheme
    assert_equal 0, AuthSourceOutOfBand.count
  end
  def test_email_can_be_deactivated_with_native_confirmation
    password_login
    post '/account/twofa', params: { twofa_code: emailed_code }
    travel 31.seconds do
      post '/my/twofa/email/deactivate/init'
      assert_redirected_to '/my/twofa/email/deactivate/confirm'
      post '/my/twofa/email/deactivate', params: { twofa_code: emailed_code }
      assert_redirected_to '/my/account'
      assert_nil @user.reload.twofa_scheme
      assert_not AuthSourceOutOfBand.where(user_id: @user.id).exists?
    end
  end

  def test_login_accepts_native_backup_code
    backup = OutOfBandAuth::Email.new(@user).init_backup_codes!.first.value
    password_login
    post '/account/twofa', params: { twofa_code: backup }
    assert_redirected_to '/my/page'
    get '/my/page'
    assert_response :success
  end

end
