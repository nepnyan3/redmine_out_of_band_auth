# Runs only inside an isolated Redmine 3.4.13 container. All identities are fake.
require 'json'
require 'action_dispatch/testing/integration'
ActionController::Base.allow_forgery_protection = false
ActionMailer::Base.delivery_method = :test
ActionMailer::Base.perform_deliveries = true
[Mailer, OutOfBandAuthMailer].each { |mailer| mailer.delivery_method = :test; mailer.perform_deliveries = true }
ActionMailer::Base.deliveries.clear
Setting.mail_from = 'redmine@example.test'
Setting.host_name = 'www.example.com'
Setting.autologin = '7'

def check(condition, message)
  raise message unless condition
  puts "PASS legacy: #{message}"
end

password = 'Legacy-login-test-123'
users = {}
[['migration_email', true], ['migration_disabled', false]].each do |login, enabled|
  user = User.create!(:login => login, :firstname => 'Migration', :lastname => 'Test',
                      :mail => "#{login}@example.test",
                      :language => 'en')
  user.password = password
  user.password_confirmation = password
  user.save!
  user.pref.enabled_out_of_band_auth = enabled ? '1' : '0'
  user.pref.save!
  users[login] = user
end
user = users.fetch('migration_email')
session = ActionDispatch::Integration::Session.new(Rails.application)
session.post '/login', :username => user.login, :password => password, :autologin => '1'
check(session.response.status == 302, 'password login redirects')
session.get '/my/page'
check(session.response.redirect_url.end_with?('/out_of_band_auths/login'), 'old plugin requires its email challenge')
code = user.reload.verification_code
check(code.to_s.match(/\A\d{6}\z/), 'old plugin generated six digit code')
check(ActionMailer::Base.deliveries.any? { |mail| mail.destinations.include?(user.mail) }, 'challenge email delivered to test mailbox')
session.post '/out_of_band_auths/login', :password => 'invalid'
check(session.response.status == 200, 'invalid legacy code does not complete challenge')
mail = ActionMailer::Base.deliveries.last
emailed_code = (mail.text_part || mail).body.decoded[/\b[0-9]{6}\b/]
check(emailed_code == code, 'emailed legacy code matches the stored challenge')
session.post '/out_of_band_auths/login', :password => emailed_code
check(session.response.redirect_url.end_with?('/my/page'), 'old email code completes login')
session.get '/my/page'
check(session.response.status == 200, 'old authenticated user can open My page')
check(user.reload.verification_code.blank?, 'successful legacy challenge is consumed')
check(Token.where(:user_id => user.id, :action => 'autologin').exists?, 'legacy remember-me token exists before upgrade')
# Save a real outstanding challenge as well; migration must discard it.
user.generate_verification_code
check(user.reload.verification_code.present?, 'legacy outstanding challenge exists before upgrade')
user.generate_session_token
baseline = {
  'redmine_version' => Redmine::VERSION.to_s,
  'ruby_version' => RUBY_VERSION,
  'rails_version' => Rails.version,
  'users' => users.transform_values { |u| { 'id' => u.id, 'login' => u.login, 'mail' => u.mail, 'hashed_password' => u.hashed_password, 'salt' => u.salt } }
}
File.write('/usr/src/redmine/db/legacy-baseline.json', JSON.pretty_generate(baseline))
puts 'LEGACY_AUTHENTICATION_PASS'
