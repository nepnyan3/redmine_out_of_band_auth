#!/usr/bin/env bash
set -euo pipefail
cd /usr/src/redmine
export RAILS_ENV=test
bundle check
bundle exec rake generate_secret_token db:migrate
bundle exec rake redmine:plugins:migrate NAME=redmine_out_of_band_auth VERSION=1
bundle exec rails runner plugins/redmine_out_of_band_auth/test/upgrade_seed.rb
bundle exec rake redmine:plugins:migrate NAME=redmine_out_of_band_auth
bundle exec rails runner plugins/redmine_out_of_band_auth/test/upgrade_check.rb
bundle exec rake zeitwerk:check
bundle exec rake redmine:plugins:test NAME=redmine_out_of_band_auth
DATABASE_URL=sqlite3:/usr/src/redmine/db/test.sqlite3 RAILS_ENV=development bundle exec rails runner plugins/redmine_out_of_band_auth/test/reload_check.rb
