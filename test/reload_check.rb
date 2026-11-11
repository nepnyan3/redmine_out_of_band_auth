2.times do
  Rails.application.reloader.reload!
  raise 'Email scheme did not reload' unless Redmine::Twofa.for_twofa_scheme('email') == OutOfBandAuth::Email
  raise 'TOTP scheme was lost' unless Redmine::Twofa.for_twofa_scheme('totp') == Redmine::Twofa::Totp
end
puts 'Development reload passed'
