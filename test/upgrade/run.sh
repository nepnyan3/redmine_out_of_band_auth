#!/usr/bin/env bash
set -euo pipefail
root=$(cd "$(dirname "$0")/../.." && pwd)
artifacts=${ARTIFACT_DIRECTORY:-$(mktemp -d)}
mkdir -p "$artifacts"
artifacts=$(cd "$artifacts" && pwd)
legacy_commit=45e8c909baef2df161d23f5648ef95844f8e3507
legacy_image=redmine:3.4.13@sha256:3827122e3c22810ed3c93cdeb0ec45f2f9c42e40447629c73f8c82a5c262f46d
legacy_container="redmine-oob-upgrade-$(date +%s)-$$"
trap 'docker rm -f "$legacy_container" >/dev/null 2>&1 || true' EXIT
# Full history is required. Only synthetic test data is created.
git -C "$root" archive "$legacy_commit" -o "$artifacts/legacy-plugin.tar"
docker pull "$legacy_image"
docker run --name "$legacy_container" --network none \
  --mount "type=bind,src=$root/test/upgrade,dst=/validation,readonly" \
  --mount "type=bind,src=$artifacts,dst=/input,readonly" \
  --entrypoint bash "$legacy_image" /validation/legacy.sh
docker cp "$legacy_container:/usr/src/redmine/db/migration.sqlite3" "$artifacts/migration.sqlite3"
docker cp "$legacy_container:/usr/src/redmine/db/legacy-baseline.json" "$artifacts/legacy-baseline.json"
docker run --rm --network none \
  --mount "type=bind,src=$root,dst=/usr/src/redmine/plugins/redmine_out_of_band_auth,readonly" \
  --mount "type=bind,src=$artifacts/migration.sqlite3,dst=/input/migration.sqlite3,readonly" \
  --mount "type=bind,src=$artifacts/legacy-baseline.json,dst=/input/legacy-baseline.json,readonly" \
  "${TEST_IMAGE:-redmine-oob-test}" bash plugins/redmine_out_of_band_auth/test/upgrade/migrated.sh
printf 'Upgrade passed. Synthetic source DB and baseline retained at: %s\n' "$artifacts"
