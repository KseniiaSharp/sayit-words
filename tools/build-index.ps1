<#
Builds index.json, the pack catalog the app downloads first.
Hand-edited fields (name, level, tags, idFrom, idTo) are kept from the existing index.json; id, pair,
file, words and sha256 are computed from the packs, and version is raised whenever a pack's sha256
changes. A pack without an entry gets one with the next free id block of 10000.
sha256 is taken over the LF form of the file, which is what GitHub serves (see .gitattributes).
  -Check  do not write; exit 1 when index.json is out of date (used by CI)
#>
param(
    [string]$Root = (Split-Path -Parent $PSScriptRoot),
    [switch]$Check
)

$ErrorActionPreference = 'Stop'

$Root = (Resolve-Path $Root).Path
$indexPath = Join-Path $Root 'index.json'
$utf8 = New-Object System.Text.UTF8Encoding($false)
$sha = [Security.Cryptography.SHA256]::Create()

$old = [ordered]@{}
$oldText = ''
if (Test-Path $indexPath) {
    $oldText = [IO.File]::ReadAllText($indexPath, $utf8).Replace("`r`n", "`n")
    foreach ($p in @(($oldText | ConvertFrom-Json).packs)) { $old[[string]$p.file] = $p }
}
$maxTo = 0
foreach ($p in $old.Values) { if ([int]$p.idTo -gt $maxTo) { $maxTo = [int]$p.idTo } }

$files = @(Get-ChildItem -Path $Root -Filter *.data -Recurse -File |
    Where-Object { $_.FullName -notmatch '[\\/]\.git[\\/]' } | Sort-Object FullName)

$entries = @()
foreach ($file in $files) {
    $rel = $file.FullName.Substring($Root.Length + 1).Replace('\', '/')
    $text = $utf8.GetString([IO.File]::ReadAllBytes($file.FullName)).Replace("`r`n", "`n")
    $hash = -join ($sha.ComputeHash($utf8.GetBytes($text)) | ForEach-Object { $_.ToString('x2') })
    $words = @($text.Split("`n") | Where-Object { $_.Trim().Length -gt 0 }).Count

    $prev = $old[$rel]
    if ($prev) {
        $name = [string]$prev.name
        $level = $prev.level
        $tags = @($prev.tags | Where-Object { $_ })
        $from = [int]$prev.idFrom
        $to = [int]$prev.idTo
        $version = [int]$prev.version
        if ($version -lt 1) { $version = 1 }
        elseif ($prev.sha256 -and $prev.sha256 -ne $hash) { $version++ }
    } else {
        $topic = [IO.Path]::GetFileNameWithoutExtension($rel)
        $name = ($topic.Split('-') | ForEach-Object { $_.Substring(0, 1).ToUpper() + $_.Substring(1) }) -join ' '
        $level = $null
        $tags = @()
        $from = [int]([math]::Floor($maxTo / 10000) * 10000 + 10001)
        $to = $from + 9998
        $maxTo = $to
        $version = 1
        Write-Output ('New pack {0}: id block {1} - {2}. Check its name, level and tags in index.json.' -f $rel, $from, $to)
    }

    $entries += [pscustomobject][ordered]@{
        id      = $rel.Substring(0, $rel.Length - '.data'.Length)
        pair    = $rel.Split('/')[0].ToUpperInvariant()
        name    = $name
        level   = $level
        tags    = $tags
        file    = $rel
        version = $version
        words   = $words
        idFrom  = $from
        idTo    = $to
        sha256  = $hash
    }
}

$found = @($entries | ForEach-Object { $_.file })
$missing = @($old.Keys | Where-Object { $found -notcontains $_ })
foreach ($m in $missing) { Write-Output ('ERROR: index.json lists {0}, but the file is missing' -f $m) }
if ($missing.Count -gt 0) { exit 1 }

function ConvertTo-JsonValue($Value) {
    if ($null -eq $Value) { return 'null' }
    if ($Value -is [int]) { return [string]$Value }
    if ($Value -is [array]) { return '[' + (($Value | ForEach-Object { ConvertTo-JsonValue $_ }) -join ', ') + ']' }
    return '"' + ([string]$Value).Replace('\', '\\').Replace('"', '\"') + '"'
}

# Hand-written JSON so Windows PowerShell 5.1 and pwsh 7 (CI) produce identical bytes.
$packs = foreach ($e in @($entries | Sort-Object idFrom)) {
    $fields = foreach ($prop in $e.PSObject.Properties) {
        '      "{0}": {1}' -f $prop.Name, (ConvertTo-JsonValue $prop.Value)
    }
    "    {`n" + ($fields -join ",`n") + "`n    }"
}
$newText = "{`n  `"schemaVersion`": 1,`n  `"packs`": [`n" + (@($packs) -join ",`n") + "`n  ]`n}`n"

if ($Check) {
    if ($newText -eq $oldText) { Write-Output 'index.json is up to date.'; exit 0 }
    Write-Output 'ERROR: index.json is out of date. Run tools/build-index.ps1 and commit the result.'
    exit 1
}

foreach ($e in $entries) { Write-Output ('{0}: {1} words, version {2}, sha256 {3}' -f $e.id, $e.words, $e.version, $e.sha256) }
if ($newText -eq $oldText) { Write-Output 'index.json unchanged.'; exit 0 }
[IO.File]::WriteAllText($indexPath, $newText, $utf8)
Write-Output 'index.json written.'
exit 0
