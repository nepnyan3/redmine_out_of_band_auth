#!/usr/bin/env bash
set -euo pipefail
cd /usr/src/redmine
mkdir -p plugins/redmine_out_of_band_auth
tar -xf /input/legacy-plugin.tar -C plugins/redmine_out_of_band_auth
printf 'production:\n  adapter: sqlite3\n  database: /usr/src/redmine/db/migration.sqlite3\n  timeout: 5000\n' > config/database.yml
export RAILS_ENV=production
bundle exec rake generate_secret_token db:migrate redmine:plugins:migrate
bundle exec rails runner /validation/legacy_login.rb
