# Redmine Out of Band Auth

Email verification as a native two-factor authentication scheme for **Redmine 7.0**.
Plugin version 2.0.0 is tested with Redmine 7.0.3, Rails 8.1.4, Ruby 4.0.9 and SQLite.
Older Redmine versions need the legacy plugin version.

## Usage

1. Configure Redmine's outgoing email and verify delivery with its test-email function.
2. Enable optional or required two-factor authentication in Administration → Settings.
3. Open My account → Enable email verification, then enter the code sent to your primary email address.
4. Generate and securely retain Redmine's standard backup codes.

The plugin uses Redmine's existing login, enrollment, deactivation, administrator reset,
backup-code and mandatory-2FA controls. Redmine supports one active scheme per user:
email **or** an authenticator app (TOTP). Existing TOTP settings are preserved;
email is not a fallback that bypasses an active TOTP scheme. Deactivate the current
scheme through Redmine before choosing another. Email authentication depends on the
security and availability of the mailbox; use TOTP when a separate authenticator is needed.

## Install and upgrade

Back up the database and plugin before upgrading. Install this checkout as
`plugins/redmine_out_of_band_auth` inside Redmine, then run from the Redmine root:

```sh
bundle install
RAILS_ENV=production bundle exec rake redmine:plugins:migrate NAME=redmine_out_of_band_auth
RAILS_ENV=production bundle exec rake assets:precompile
```

Restart all application processes. Use the same stable Rails secret key across all
application instances; changing it invalidates outstanding email challenges.

The migration converts legacy `enabled_out_of_band_auth` users to the native email
scheme only when they have no existing 2FA scheme. Existing TOTP/other schemes win.
Migrated users' existing login sessions and remember-me tokens are revoked by Redmine.
If native 2FA was disabled and email users were migrated, its setting becomes **optional**
so those users can complete login. Other users are not automatically enrolled.
Legacy verification codes are discarded and the plaintext-code column is removed.
This migration is irreversible: restore the pre-upgrade backup to downgrade.
The old checkbox, custom login endpoint and ciphering-task overrides are removed.

## Security behavior

- Password authentication does not establish a logged-in session or a remember-me
  cookie until Redmine's second-factor check succeeds.
- Codes are generated with `SecureRandom`, expire after two minutes, and are consumed
  under a database row lock. Only a keyed SHA-256 HMAC is stored, bound to the user.
- A challenge allows three failed/successful verification attempts in total. Resending
  does not reset its remaining attempt budget. After exhaustion, wait until expiry.
- Emails are throttled to one per user per 30 seconds; a resend replaces the old code.
  During the cooldown no new email is sent. Redmine also limits the pending login session.
- Standard Redmine behavior for REST API keys and completed remember-me logins remains
  in effect; this plugin does not add interactive 2FA to API requests.

## Tests

Docker is sufficient; no local Ruby or SMTP credentials are required:

```sh
docker build -t redmine-oob-test test/docker
docker run --rm --network none \
  --mount "type=bind,src=$PWD,dst=/usr/src/redmine/plugins/redmine_out_of_band_auth,readonly" \
  redmine-oob-test bash plugins/redmine_out_of_band_auth/test/run.sh
```

Behind a TLS-inspecting proxy, pass the trusted CA bundle to the build with
`--secret id=ca,src=/path/to/ca-bundle.pem`; certificate verification stays enabled.
The disposable container tests a legacy database upgrade, eager loading, authentication,
TOTP coexistence, expiration, replay, attempt/resend limits, enrollment, backup codes,
and development class reloading. GitHub Actions runs the same commands.

## Uninstall

Deactivate email authentication for all enrolled users through Redmine **before** removing
the plugin, otherwise they will have an unavailable 2FA scheme. Keep the data backup;
the security upgrade cannot be reversed with a down migration.

## License

[MIT](LICENSE)
