email = User.find_by!(login: 'legacy_email')
totp = User.find_by!(login: 'legacy_totp')
raise 'Email user was not migrated' unless email.twofa_scheme == 'email'
raise 'TOTP user was overwritten' unless totp.twofa_scheme == 'totp'
raise 'Migrated session was not revoked' if Token.where(user_id: email.id, action: ['session', 'autologin']).exists?
raise 'Native confirmation is disabled' unless Setting.twofa?
raise 'Old codes survived migration' if AuthSourceOutOfBand.exists?
raise 'Plaintext column survived migration' if AuthSourceOutOfBand.column_names.include?('verification_code')
puts 'Legacy upgrade, TOTP preservation and session revocation passed'
