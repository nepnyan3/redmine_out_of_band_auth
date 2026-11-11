# Run with rails runner after a real legacy DB has completed both migrations.
require 'json'
require 'action_dispatch/testing/integration'
ActionController::Base.allow_forgery_protection = false
ActionMailer::Base.delivery_method = :test
ActionMailer::Base.perform_deliveries = true
ActionMailer::Base.deliveries.clear

def check(condition, message)
  raise message unless condition
  puts "PASS migrated: #{message}"
end

def emailed_code
  mail = ActionMailer::Base.deliveries.last
  raise 'No email delivered' unless mail
  (mail.text_part || mail).body.decoded[/\b[0-9]{6}\b/]
end

baseline = JSON.parse(File.read('/input/legacy-baseline.json'))
password = 'Legacy-login-test-123'
email = User.find_by!(login: 'migration_email')
disabled = User.find_by!(login: 'migration_disabled')
baseline.fetch('users').each do |login, before|
  user = User.find_by!(login: login)
  %w[id login mail hashed_password salt].each do |attribute|
    check(user.public_send(attribute) == before.fetch(attribute), "#{login} retains #{attribute}")
  end
end
check(email.twofa_scheme == 'email', 'legacy enabled user is automatically enrolled in email scheme')
check(disabled.twofa_scheme.blank?, 'legacy disabled user is not enrolled')
check(Setting.twofa == '1', 'native two-factor authentication is optional after migration')
check(!Token.where(user_id: email.id, action: %w[autologin session]).exists?, 'old session and remember-me tokens are revoked')
check(AuthSourceOutOfBand.count == 0, 'outstanding legacy codes are discarded')
check(!AuthSourceOutOfBand.column_names.include?('verification_code'), 'plaintext legacy column is removed')

session = ActionDispatch::Integration::Session.new(Rails.application)
session.post '/login', params: {username: email.login, password: password, autologin: '1'}
check(session.response.redirect_url.end_with?('/account/twofa/confirm'), 'original password reaches native second-factor challenge')
check(session.cookies['autologin'].blank?, 'remember-me cookie is absent before second factor')
code = emailed_code
check(code.to_s.match?(/\A\d{6}\z/), 'new email challenge generated')
check(ActionMailer::Base.deliveries.last.to.include?(email.mail), 'new challenge uses original primary email')
session.get '/my/account'
check(session.response.redirect_url.include?('/login'), 'account is inaccessible before second factor')
session.post '/account/twofa', params: {twofa_code: 'invalid'}
check(!session.response.redirect_url.to_s.end_with?('/my/page'), 'incorrect new code is rejected')
session.post '/account/twofa', params: {twofa_code: code}
check(session.response.redirect_url.end_with?('/my/page'), 'new code completes login without re-enrollment')
check(session.cookies['autologin'].present?, 'remember-me cookie issued only after second factor')
session.get '/my/page'
check(session.response.status == 200, 'migrated user can open My page')
check(!OutOfBandAuth::Email.new(email).verify_otp!(code), 'consumed code cannot be replayed')

backup = OutOfBandAuth::Email.new(email).init_backup_codes!.first.value
backup_session = ActionDispatch::Integration::Session.new(Rails.application)
backup_session.post '/login', params: {username: email.login, password: password}
backup_session.post '/account/twofa', params: {twofa_code: backup}
check(backup_session.response.redirect_url.end_with?('/my/page'), 'migrated user can use native backup codes')

plain_session = ActionDispatch::Integration::Session.new(Rails.application)
plain_session.post '/login', params: {username: disabled.login, password: password}
check(plain_session.response.redirect_url.end_with?('/my/page'), 'previously disabled user can still login without enrollment')
puts "Migration: Redmine #{baseline['redmine_version']} / Rails #{baseline['rails_version']} / Ruby #{baseline['ruby_version']} -> Redmine #{Redmine::VERSION} / Rails #{Rails.version} / Ruby #{RUBY_VERSION}"
puts 'REAL_LEGACY_UPGRADE_AUTHENTICATION_PASS'
