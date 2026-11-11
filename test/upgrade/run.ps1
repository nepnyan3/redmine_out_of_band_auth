param(
    [string]$TestImage = 'redmine-oob-test',
    [string]$ArtifactDirectory = (Join-Path ([IO.Path]::GetTempPath()) ('redmine-oob-upgrade-' + [guid]::NewGuid().ToString('N')))
)
$ErrorActionPreference = 'Stop'
$root = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$legacyCommit = '45e8c909baef2df161d23f5648ef95844f8e3507'
$legacyImage = 'redmine:3.4.13@sha256:3827122e3c22810ed3c93cdeb0ec45f2f9c42e40447629c73f8c82a5c262f46d'
$legacyContainer = 'redmine-oob-upgrade-' + [guid]::NewGuid().ToString('N')
New-Item -ItemType Directory -Path $ArtifactDirectory -Force | Out-Null
$artifacts = (Resolve-Path $ArtifactDirectory).Path
function Run-Checked([string]$Program, [string[]]$Arguments) {
    & $Program @Arguments
    if ($LASTEXITCODE -ne 0) { throw "$Program failed with exit code $LASTEXITCODE" }
}
try {
    # Checkout history is required; CI uses fetch-depth: 0. No production DB is read.
    Run-Checked 'git' @('-C', $root, 'archive', $legacyCommit, '-o', (Join-Path $artifacts 'legacy-plugin.tar'))
    Run-Checked 'docker' @('pull', $legacyImage)
    Run-Checked 'docker' @('run', '--name', $legacyContainer, '--network', 'none',
        '--mount', "type=bind,src=$PSScriptRoot,dst=/validation,readonly",
        '--mount', "type=bind,src=$artifacts,dst=/input,readonly",
        '--entrypoint', 'bash', $legacyImage, '/validation/legacy.sh')
    Run-Checked 'docker' @('cp', "${legacyContainer}:/usr/src/redmine/db/migration.sqlite3", (Join-Path $artifacts 'migration.sqlite3'))
    Run-Checked 'docker' @('cp', "${legacyContainer}:/usr/src/redmine/db/legacy-baseline.json", (Join-Path $artifacts 'legacy-baseline.json'))
    Run-Checked 'docker' @('run', '--rm', '--network', 'none',
        '--mount', "type=bind,src=$root,dst=/usr/src/redmine/plugins/redmine_out_of_band_auth,readonly",
        '--mount', "type=bind,src=$artifacts,dst=/input,readonly",
        $TestImage, 'bash', 'plugins/redmine_out_of_band_auth/test/upgrade/migrated.sh')
    Write-Output "Upgrade passed. Synthetic source DB and baseline retained at: $artifacts"
}
finally {
    # Only the uniquely named disposable container created by this script is removed.
    & docker rm -f $legacyContainer 2>$null | Out-Null
}
