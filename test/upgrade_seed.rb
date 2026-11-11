# Run only against a disposable test DB after plugin migration VERSION=1.
Setting.twofa = '0'
[['legacy_email', nil], ['legacy_totp', 'totp']].each do |login, scheme|
  user = User.create!(login: login, firstname: 'Legacy', lastname: 'Test',
                      mail: "#{login}@example.test", password: 'test-password-123',
                      password_confirmation: 'test-password-123', twofa_scheme: scheme)
  user.pref[:enabled_out_of_band_auth] = '1'
  user.pref.save!
  user.generate_autologin_token
  user.generate_session_token
end
ActiveRecord::Base.connection.execute("INSERT INTO auth_source_out_of_bands (user_id, verification_code) VALUES (1, '123456')")
