# Redmine Out of Band Auth

[日本語](README.ja.md) | English

Email verification as a native two-factor authentication (2FA) scheme for **Redmine 7.0**.
This branch contains plugin version **2.0.0**, targeting Redmine **7.0.3**, Rails **8.1.4**,
Ruby **4.0.9**, and SQLite for its automated tests. Older Redmine versions need the
legacy plugin version. See [Tests](#tests) for the reproducible test procedure and its scope.

## Before you start

- Configure and test Redmine's outgoing email before enabling email authentication.
- Use HTTPS in production. Users must be able to receive mail at their **primary email address**.
- Keep a tested database backup and an administrator recovery route before upgrading or requiring 2FA.
- Redmine supports one active 2FA scheme per user: email **or** an authenticator app (TOTP).
  Existing TOTP settings are preserved. Email is not a fallback that bypasses TOTP.
  Deactivate the current scheme through Redmine before choosing another.

## Install

Install this branch in the directory `plugins/redmine_out_of_band_auth` inside Redmine.
Do not install both the old and new plugin copies side by side.

```sh
cd /path/to/redmine
git clone --branch redmine-7-native-twofa \
  https://github.com/nepnyan3/redmine_out_of_band_auth.git \
  plugins/redmine_out_of_band_auth
bundle install
RAILS_ENV=production bundle exec rake redmine:plugins:migrate NAME=redmine_out_of_band_auth
RAILS_ENV=production bundle exec rake assets:precompile
```

Restart all application processes. On **Administration > Plugins**, confirm that
**Redmine Out of Band Authentication plugin 2.0.0** is listed.
Use the same stable Rails secret key across all application instances. Changing it
invalidates outstanding email challenges.

## Configure email authentication

The instructions below describe the Redmine 7.0.3 interface.

### 1. Verify outgoing email

Configure delivery in Redmine's `config/configuration.yml` for your environment, following
[Redmine's email configuration guide](https://www.redmine.org/projects/redmine/wiki/EmailConfiguration).
Restart Redmine after changing the file. In **Administration > Settings > Email notifications**,
check the sender address and use **Send a test email**. Confirm that the message arrives.
The plugin uses Redmine's mail configuration; it has no separate SMTP settings page.
Do not enable mandatory email 2FA until delivery works for the affected users.

### 2. Allow two-factor authentication

Open **Administration > Settings > Authentication**, set **Two-factor authentication**
to **optional**, and click **Save**. This is a practical starting point for testing enrollment.
After validating mail delivery and recovery, choose your organization's required policy
if needed. Redmine also offers a policy requiring 2FA only for administrators.

### 3. Enable email verification for your account

Open **My account**. Check your primary email address, then click **Enable email verification**
in the **Two-factor authentication** row. Redmine may ask you to confirm your password.
If the row is absent, check the site-wide 2FA setting and that the plugin is loaded.
If another scheme is already active, deactivate it first using Redmine's normal verification flow.

### 4. Confirm enrollment

Enter the six-digit code sent to your primary email address and submit the form.
The code expires after **two minutes**. Complete this step before treating the account as enrolled.
A resend is available after the **30-second** cooldown; a new code replaces the old code.

Return to **My account** and confirm that **Email verification code** is active.
Generate Redmine's standard backup codes and store them securely outside the mailbox and this repository.
Do not publish screenshots of passwords, live verification codes, or backup codes.

### 5. Check the next login

Sign out and log in again with the username and password. Enter the newly emailed code
on Redmine's second-factor screen. Password authentication alone does not complete the login.
Keep a separate administrator session available while testing a required-2FA policy.

## Upgrade from the legacy plugin

1. Back up the **database, uploaded files, Redmine configuration and secrets, and existing plugins**.
   Test restoration before proceeding.
2. Prepare a staging copy using the [Redmine upgrade guide](https://www.redmine.org/projects/redmine/wiki/RedmineUpgrade).
   Replace the legacy plugin with this branch at the same plugin directory **before booting
   the new application or running its migrations**. Include the migration fix described below.
3. From the new Redmine root, install dependencies and migrate the core and plugin:

   ```sh
   bundle install
   RAILS_ENV=production bundle exec rake db:migrate
   RAILS_ENV=production bundle exec rake redmine:plugins:migrate NAME=redmine_out_of_band_auth
   RAILS_ENV=production bundle exec rake assets:precompile
   ```

   Restart all application processes after completing the upgrade.
4. Check mail delivery, the site-wide 2FA setting, and a representative migrated user's login.
   Keep the backup until those checks and the recovery procedure are complete.

The plugin migration has the following behavior:

| Before migration | After migration |
| --- | --- |
| Legacy `enabled_out_of_band_auth` enabled, no native 2FA scheme | Native email scheme is enabled without re-enrollment |
| Legacy authentication enabled, native TOTP or another scheme already set | Existing native scheme is preserved |
| Legacy authentication disabled | Email authentication is not automatically enabled |
| Native 2FA disabled, at least one email user migrated | Site-wide 2FA becomes **optional** |

Migrated email users' existing login sessions and remember-me tokens are revoked by Redmine.
They must sign in again and use a **new** email code. Old codes are discarded, and the
legacy plaintext-code column is removed. The old checkbox, custom login endpoint, and
ciphering-task overrides no longer exist. The new scheme stores a keyed digest, so the
old `database_cipher_key` setup is not required for email codes. Keep any key still needed
for other encrypted Redmine data, such as SCM or LDAP credentials.

**The migration is irreversible.** Do not attempt a downgrade with `VERSION=0` or by
copying the old plugin over the new one. Restore the matched pre-upgrade database,
configuration, plugin, and compatible Redmine version from backup.

### Verified legacy migration

On **2026-11-11**, a synthetic user completed email authentication on a real
**Redmine 3.4.13 / plugin 1.0.0** instance. Its **SQLite database** was then copied into
**Redmine 7.0.3 / plugin 2.0.0 with the migration fix in this change**. The same user ID,
login name, password hash, and primary email address were retained. Login with the same
password and a newly issued email code succeeded **without re-enrollment**.

The old instance passed **11 checks**, the upgraded instance passed **28 checks**, and
the existing regression suite passed **20 tests / 144 assertions** with no failures,
errors, or skips. Old sessions and codes were invalidated, unenrolled users remained
unenrolled, and native backup-code login succeeded.
See the [migration verification report](docs/verification/redmine-7-migration.md)
for exact versions, pinned images, procedures, and limitations.

The verification also found and fixed stale model-column metadata when core and plugin
migrations run in the **same rake process**. Without that fix, an old enabled user's
native email scheme could remain unset. Replacing a migration file does **not** rerun a
migration already recorded as applied. If an earlier version already migrated your
installation, inspect a restored backup copy and plan recovery rather than manually
rewinding a production database.

This is an application-level HTTP integration check with intercepted test email, not a
browser interaction or production SMTP test. Other old Redmine releases, MySQL,
PostgreSQL, all LDAP/SSO paths, and production-specific data/plugin combinations were
not verified. Validate a backup of your own installation before production rollout.

## Security behavior and troubleshooting

- Codes are generated with `SecureRandom`, expire after two minutes, and are consumed
  under a database row lock. Only a user-bound, keyed SHA-256 HMAC is stored.
- A challenge allows **three verification attempts total**. Resending does not reset
  the attempt budget. After exhaustion, wait for expiry before starting again.
- Emails are throttled to one per user per 30 seconds. During the cooldown no new mail
  is sent. A successful resend replaces the previous code. Redmine also limits pending login sessions.
- No logged-in session or remember-me cookie is established until the second-factor check succeeds.
- If no email arrives, check the primary address, spam folder, Redmine mail configuration,
  application logs, and mail-server delivery status. Never send real credentials or codes in a bug report.
- If a code fails, use the newest message and check the two-minute expiry and attempt limit.
- If the mailbox is unavailable, use a previously saved Redmine backup code or contact a
  trusted administrator for Redmine's normal 2FA reset procedure after identity verification.
- Standard Redmine behavior for REST API keys and completed remember-me logins remains
  in effect; this plugin does not add interactive 2FA to API requests.
- Email authentication depends on mailbox security and availability. Use TOTP when a
  separate authenticator is needed.

## Tests

Docker is sufficient; no local Ruby or SMTP credentials are required. Run these commands
from the plugin checkout (POSIX shell syntax):

```sh
docker build -t redmine-oob-test test/docker
docker run --rm --network none \
  --mount "type=bind,src=$PWD,dst=/usr/src/redmine/plugins/redmine_out_of_band_auth,readonly" \
  redmine-oob-test bash plugins/redmine_out_of_band_auth/test/run.sh
```

Behind a TLS-inspecting proxy, pass the trusted CA bundle to the build with
`--secret id=ca,src=/path/to/ca-bundle.pem`; keep certificate verification enabled.
The disposable container checks a recreated legacy database upgrade, eager loading,
authentication, TOTP coexistence, expiration, replay, attempt/resend limits, enrollment,
backup codes, and development class reloading. GitHub Actions runs the same commands.
These checks do not send mail to an external SMTP service.

### Reproduce the real legacy database upgrade

Build `redmine-oob-test` as above. Use a checkout containing the full Git history so
that the runner can export the pinned legacy plugin commit.

Windows PowerShell (executed end to end during this verification):

```powershell
.\test\upgrade\run.ps1 -TestImage redmine-oob-test
```

Linux / Bash (also used by GitHub Actions):

```sh
TEST_IMAGE=redmine-oob-test bash test/upgrade/run.sh
```

The runners use pinned official Redmine images, create only synthetic users, and run
both versions with `--network none`. No production database is read and no external
email is sent. They remove their disposable containers and retain the synthetic source
SQLite database and comparison JSON in the printed temporary directory.

## Uninstall

Deactivate email authentication for **all enrolled users through Redmine before removing**
the plugin. Otherwise they will have an unavailable 2FA scheme. Keep the database backup;
the security upgrade cannot be reversed with a down migration.

## Created with Codex

This setup documentation and Japanese translation were created
with **OpenAI Codex** as part of the Redmine 7 verification work. The original plugin is
by Matsukei Co., Ltd.; original copyright and license notices are retained. Codex assistance
is not a certification of security or compatibility. Review the code and validate your environment.

## License

[MIT](LICENSE)
