<#
Checks every <pair>/<topic>.data pack: UTF-8 without BOM, `id|foreign|translation[|grammar|example]`
lines, ids inside the pack's block and unique across the repo. Duplicate foreign words within a
pair are reported as warnings. Exit code 1 when any error is found.
#>
param([string]$Root = (Split-Path -Parent $PSScriptRoot))

$ErrorActionPreference = 'Stop'

# Id block of every pack. Keep in sync with the table in README.md.
$Ranges = [ordered]@{
    'en-ru/it-interview.data' = @(1, 99999)
    'de-ru/a1-exam.data'      = @(100001, 109999)
}

$ci = $env:GITHUB_ACTIONS -eq 'true'
$script:errors = 0
$script:warnings = 0

function Report([string]$Level, [string]$File, [int]$Line, [string]$Text) {
    if ($Level -eq 'error') { $script:errors++ } else { $script:warnings++ }
    if ($ci) { Write-Output ('::{0} file={1},line={2}::{3}' -f $Level, $File, $Line, $Text) }
    else { Write-Output ('{0}: {1}:{2}: {3}' -f $Level.ToUpper(), $File, $Line, $Text) }
}

$Root = (Resolve-Path $Root).Path
$utf8 = New-Object System.Text.UTF8Encoding($false, $true)
$files = @(Get-ChildItem -Path $Root -Filter *.data -Recurse -File |
    Where-Object { $_.FullName -notmatch '[\\/]\.git[\\/]' } | Sort-Object FullName)

$ids = @{}
$foreign = @{}
$total = 0

foreach ($file in $files) {
    $rel = $file.FullName.Substring($Root.Length + 1).Replace('\', '/')
    if (-not $Ranges.Contains($rel)) {
        Report 'error' $rel 1 'Pack has no id range in tools/validate.ps1'
        continue
    }
    $from, $to = $Ranges[$rel]
    $pair = $rel.Split('/')[0]

    $bytes = [IO.File]::ReadAllBytes($file.FullName)
    if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) {
        Report 'error' $rel 1 'File starts with a UTF-8 BOM'
    }
    try { $text = $utf8.GetString($bytes) }
    catch { Report 'error' $rel 1 'File is not valid UTF-8'; continue }
    # Windows working copies may keep CRLF; the committed file is LF because of .gitattributes.
    if ($ci -and $text.Contains("`r")) { Report 'error' $rel 1 'CRLF line endings, use LF' }

    $count = 0
    $lines = $text.Split("`n")
    for ($i = 0; $i -lt $lines.Length; $i++) {
        $n = $i + 1
        $line = $lines[$i].TrimEnd("`r")
        if ($line.Trim().Length -eq 0) { continue }

        $parts = $line.Split('|')
        if ($parts.Length -lt 3 -or $parts.Length -gt 5) {
            Report 'error' $rel $n ("Expected 3 to 5 fields separated by '|', found {0}" -f $parts.Length)
            continue
        }
        $id = 0
        if (-not [int]::TryParse($parts[0].Trim(), [ref]$id)) {
            Report 'error' $rel $n ("Id '{0}' is not a number" -f $parts[0])
            continue
        }
        if ($id -lt $from -or $id -gt $to) {
            Report 'error' $rel $n ('Id {0} is outside the pack range {1} - {2}' -f $id, $from, $to)
        }
        if ($ids.ContainsKey($id)) {
            Report 'error' $rel $n ('Duplicate id {0}, first used at {1}' -f $id, $ids[$id])
        } else {
            $ids[$id] = '{0}:{1}' -f $rel, $n
        }
        if ($parts[1].Trim().Length -eq 0 -or $parts[2].Trim().Length -eq 0) {
            Report 'error' $rel $n 'Foreign word or translation is empty'
        }
        $key = '{0}|{1}' -f $pair, $parts[1].Trim().ToLowerInvariant()
        if ($foreign.ContainsKey($key)) {
            Report 'warning' $rel $n ("Foreign word '{0}' already at {1}" -f $parts[1].Trim(), $foreign[$key])
        } else {
            $foreign[$key] = '{0}:{1}' -f $rel, $n
        }
        $count++
    }
    $total += $count
    Write-Output ('{0}: {1} words' -f $rel, $count)
}

foreach ($pack in $Ranges.Keys) {
    if (-not (Test-Path (Join-Path $Root $pack))) { Report 'error' $pack 1 'Pack listed in tools/validate.ps1 is missing' }
}

Write-Output ('Checked {0} words in {1} packs: {2} errors, {3} warnings.' -f $total, $files.Count, $script:errors, $script:warnings)
exit ([int]($script:errors -gt 0))
