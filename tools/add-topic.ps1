<#
Adds a seed topic (a new pack <pair>/<slug>.data) from a list of generated words, or appends to the pack
when it already exists. Used by the "create seed topic:<topic>" skill (.agents/skills/create-seed-topic).

Input file: UTF-8, one candidate per line, without ids:
    foreign|translation[|grammar|example]
Candidates whose foreign word is already in any pack of the same pair (or earlier in the input) are skipped
and listed. The pack gets the next free id block of 10000 from index.json; new words get the next free ids
of the block. The script then writes index.json (name, level, tags), adds the README row and runs
tools/build-index.ps1 and tools/validate.ps1.
  -DryRun   only report what would be added, write nothing
  -Publish  then commit, push and wait for the pipeline (tools/publish.ps1)
Exit code: 0 success, 1 error, 3 nothing new to add.
#>
param(
    [Parameter(Mandatory)][ValidatePattern('^[a-z]{2}-[a-z]{2}$')][string]$Pair,
    [Parameter(Mandatory)][string]$Topic,
    [Parameter(Mandatory)][string]$InputFile,
    [string]$Slug,
    [string]$Level,
    [string[]]$Tags = @(),
    [string]$Root,
    [switch]$DryRun,
    [switch]$Publish
)

$ErrorActionPreference = 'Stop'

# $PSScriptRoot is empty in param defaults of advanced scripts on Windows PowerShell 5.1.
if (-not $Root) { $Root = Split-Path -Parent $PSScriptRoot }
$Root = (Resolve-Path $Root).Path
$utf8 = New-Object System.Text.UTF8Encoding($false)
$indexPath = Join-Path $Root 'index.json'

if (-not $Slug) { $Slug = ($Topic.ToLowerInvariant() -replace '[^a-z0-9]+', '-').Trim('-') }
if ($Slug -notmatch '^[a-z0-9]+(-[a-z0-9]+)*$') { Write-Output "ERROR: invalid slug '$Slug', pass -Slug"; exit 1 }
$rel = '{0}/{1}.data' -f $Pair, $Slug
$packPath = Join-Path $Root $rel

# Comparison key for duplicates: lowercase, single spaces, without a leading article or "to".
function Get-Key([string]$Foreign) {
    $k = ($Foreign.Trim().ToLowerInvariant() -replace '\s+', ' ')
    $k = $k -replace '^(der|die|das|the|a|an|to) ', ''
    return $k
}

function Read-Lines([string]$Path) {
    $utf8.GetString([IO.File]::ReadAllBytes($Path)).TrimStart([char]0xFEFF).Replace("`r`n", "`n").Split("`n") |
        Where-Object { $_.Trim().Length -gt 0 }
}

# Foreign words already used in this pair.
$known = @{}
$maxId = 0
$minId = 0
foreach ($file in @(Get-ChildItem -Path (Join-Path $Root $Pair) -Filter *.data -File -ErrorAction SilentlyContinue)) {
    $fileRel = '{0}/{1}' -f $Pair, $file.Name
    foreach ($line in Read-Lines $file.FullName) {
        $parts = $line.Split('|')
        if ($parts.Length -lt 3) { continue }
        $key = Get-Key $parts[1]
        if (-not $known.ContainsKey($key)) { $known[$key] = '{0} ({1})' -f $parts[1].Trim(), $fileRel }
        if ($fileRel -eq $rel) {
            $id = [int]$parts[0]
            if ($id -gt $maxId) { $maxId = $id }
            if ($minId -eq 0 -or $id -lt $minId) { $minId = $id }
        }
    }
}

$new = New-Object System.Collections.Generic.List[string]
$dupes = New-Object System.Collections.Generic.List[string]
$bad = 0
$n = 0
foreach ($line in Read-Lines (Resolve-Path $InputFile).Path) {
    $n++
    $parts = @($line.Split('|') | ForEach-Object { $_.Trim() })
    if ($parts.Length -ge 3 -and $parts[0] -match '^\d+$') { $parts = $parts[1..($parts.Length - 1)] }
    if ($parts.Length -lt 2 -or $parts.Length -gt 4 -or $parts[0].Length -eq 0 -or $parts[1].Length -eq 0) {
        Write-Output ("SKIP line {0}: expected foreign|translation[|grammar|example]: {1}" -f $n, $line)
        $bad++
        continue
    }
    $key = Get-Key $parts[0]
    if ($known.ContainsKey($key)) {
        $dupes.Add(('{0} = {1}' -f $parts[0], $known[$key]))
        continue
    }
    $known[$key] = '{0} (input line {1})' -f $parts[0], $n
    # Trailing empty fields are dropped so EN-RU lines stay id|foreign|translation.
    while ($parts.Length -gt 2 -and $parts[-1].Length -eq 0) { $parts = $parts[0..($parts.Length - 2)] }
    $new.Add(($parts -join '|'))
}

# Id block: existing entry, or the next free block of 10000 after the highest idTo.
$index = if (Test-Path $indexPath) { [IO.File]::ReadAllText($indexPath, $utf8) | ConvertFrom-Json } else { $null }
$packs = @(if ($index) { $index.packs })
$entry = $packs | Where-Object { $_.file -eq $rel } | Select-Object -First 1
if ($entry) {
    $from = [int]$entry.idFrom; $to = [int]$entry.idTo
} else {
    $maxTo = 0
    foreach ($p in $packs) { if ([int]$p.idTo -gt $maxTo) { $maxTo = [int]$p.idTo } }
    $from = [int]([math]::Floor($maxTo / 10000) * 10000 + 10001)
    $to = $from + 9998
}
$next = [math]::Max($maxId + 1, $from)
$last = $next + $new.Count - 1
if ($to -ge 1000000) { Write-Output 'ERROR: no free id block below 1000000'; exit 1 }
if ($new.Count -gt 0 -and $last -gt $to) { Write-Output ('ERROR: {0} words do not fit into {1} - {2}' -f $new.Count, $from, $to); exit 1 }

$action = if ($entry -or (Test-Path $packPath)) { 'append to' } else { 'new pack' }
Write-Output ('{0} {1} "{2}": {3} candidates, {4} new, {5} duplicates, {6} invalid; ids {7} - {8} (block {9} - {10})' -f
    $action, $rel, $Topic, $n, $new.Count, $dupes.Count, $bad, $next, $last, $from, $to)
foreach ($d in $dupes) { Write-Output "  duplicate: $d" }

if ($new.Count -eq 0) { Write-Output 'Nothing new to add.'; exit 3 }
if ($DryRun) { exit 0 }

# Pack file, UTF-8 without BOM, LF.
$lines = for ($i = 0; $i -lt $new.Count; $i++) { '{0}|{1}' -f ($next + $i), $new[$i] }
$existing = if (Test-Path $packPath) { $utf8.GetString([IO.File]::ReadAllBytes($packPath)).Replace("`r`n", "`n") } else { '' }
if ($existing.Length -gt 0 -and -not $existing.EndsWith("`n")) { $existing += "`n" }
New-Item -ItemType Directory -Force (Split-Path -Parent $packPath) | Out-Null
[IO.File]::WriteAllText($packPath, $existing + (($lines -join "`n") + "`n"), $utf8)

# index.json entry with the hand-edited fields; build-index.ps1 fills in the rest and formats the file.
if (-not $entry) {
    $entry = [pscustomobject][ordered]@{ file = $rel; name = $Topic; level = $null; tags = @(); idFrom = $from; idTo = $to }
    $packs += $entry
}
if ($Level) { $entry.level = $Level }
$Tags = @($Tags -split ',' | ForEach-Object { $_.Trim().ToLowerInvariant() } | Where-Object { $_ })
if ($Tags.Count -gt 0) { $entry.tags = $Tags }
$doc = [pscustomobject][ordered]@{ schemaVersion = 1; packs = @($packs) }
[IO.File]::WriteAllText($indexPath, ($doc | ConvertTo-Json -Depth 5), $utf8)

& (Join-Path $PSScriptRoot 'build-index.ps1') -Root $Root
if ($LASTEXITCODE -ne 0) { exit 1 }

# README id table: add the row of a new pack or update the "Used" column.
$readmePath = Join-Path $Root 'README.md'
if (Test-Path $readmePath) {
    $packId = $rel.Substring(0, $rel.Length - '.data'.Length)
    $usedFrom = if ($minId -gt 0) { $minId } else { $next }
    $row = '| {0} | {1} - {2} | {3} - {4} |' -f $packId, $from, $to, $usedFrom, $last
    $readme = [Collections.Generic.List[string]]($utf8.GetString([IO.File]::ReadAllBytes($readmePath)).Replace("`r`n", "`n").Split("`n"))
    $at = -1; $lastRow = -1
    for ($i = 0; $i -lt $readme.Count; $i++) {
        if ($readme[$i].StartsWith("| $packId |")) { $at = $i }
        if ($readme[$i] -match '^\| [a-z]{2}-[a-z]{2}/') { $lastRow = $i }
    }
    if ($at -ge 0) { $readme[$at] = $row } elseif ($lastRow -ge 0) { $readme.Insert($lastRow + 1, $row) }
    else { Write-Output 'WARNING: README id table not found, add the row by hand.' }
    [IO.File]::WriteAllText($readmePath, ($readme -join "`n"), $utf8)
}

& (Join-Path $PSScriptRoot 'validate.ps1') -Root $Root
if ($LASTEXITCODE -ne 0) { Write-Output 'Validation failed, fix the pack before publishing.'; exit 1 }

if ($Publish) {
    & (Join-Path $PSScriptRoot 'publish.ps1') -Message ('Add seed topic {0}: {1} words' -f $rel.Replace('.data', ''), $new.Count)
    exit $LASTEXITCODE
}
exit 0
