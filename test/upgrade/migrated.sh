#!/usr/bin/env bash
set -euo pipefail
cd /usr/src/redmine
# Input is mounted read-only. Migrate a private copy, never the source backup.
cp /input/migration.sqlite3 db/test.sqlite3
export RAILS_ENV=test
# Exercise the same-process upgrade too: model metadata must not stay stale.
bundle exec rake generate_secret_token db:migrate redmine:plugins:migrate
bundle exec rails runner plugins/redmine_out_of_band_auth/test/upgrade/migrated_login.rb
