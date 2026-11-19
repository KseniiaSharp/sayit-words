<#
Validates the packs, commits all changes, pushes the current branch and waits for the
GitHub Actions result (tools/watch-pipeline.ps1). Nothing is committed when validation fails.
  -FromSayIt      first copy the bundled seed files from ..\SayIt\Resources\Raw into the packs
  -CoAuthorJunie  add the Junie co-author trailer (use it when an agent commits)
  -NoWatch        push without waiting for the pipeline
#>
param(
    [string]$Message,
    [switch]$FromSayIt,
    [switch]$CoAuthorJunie,
    [switch]$NoWatch
)

$root = Split-Path -Parent $PSScriptRoot

# Bundled SayIt seed file of each pack, used by -FromSayIt.
$sayItSeeds = [ordered]@{
    'en-ru/it-interview.data' = 'seed.data'
    'de-ru/a1-exam.data'      = 'seed_de_a1.data'
}

if ($FromSayIt) {
    $raw = Join-Path $root '..\SayIt\Resources\Raw'
    foreach ($pack in $sayItSeeds.Keys) {
        Copy-Item (Join-Path $raw $sayItSeeds[$pack]) (Join-Path $root $pack) -Force
        Write-Output ('Copied {0} -> {1}' -f $sayItSeeds[$pack], $pack)
    }
}

& (Join-Path $PSScriptRoot 'validate.ps1') -Root $root
if ($LASTEXITCODE -ne 0) { Write-Output 'Validation failed, nothing committed.'; exit 1 }

git -C $root add -A
$changed = @(git -C $root diff --cached --name-only)
if ($changed.Count -eq 0) { Write-Output 'No changes to commit.'; exit 0 }

if (-not $Message) {
    $packs = @($changed | Where-Object { $_ -like '*.data' })
    $Message = if ($packs.Count -gt 0) { 'Update word packs: ' + ($packs -join ', ') } else { 'Update sayit-words' }
}
$commitArgs = @('-C', $root, 'commit', '-m', $Message)
if ($CoAuthorJunie) { $commitArgs += @('--trailer', 'Co-authored-by: Junie <junie@jetbrains.com>') }
git @commitArgs
if ($LASTEXITCODE -ne 0) { Write-Output 'Commit failed.'; exit 1 }

git -C $root push -u origin HEAD
if ($LASTEXITCODE -ne 0) { Write-Output 'Push failed. The commit is kept locally; fix the cause and run git push.'; exit 1 }

if ($NoWatch) { exit 0 }
& (Join-Path $PSScriptRoot 'watch-pipeline.ps1') -Sha (git -C $root rev-parse HEAD).Trim()
exit $LASTEXITCODE
