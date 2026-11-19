<#
Waits until every GitHub Actions run for a commit has finished, then prints each run, its jobs,
steps and annotations. Exit code: 0 all runs succeeded, 1 a run failed, 2 timeout.
Uses the public API without a login (60 requests per hour); set GITHUB_TOKEN to raise the limit.
#>
param(
    [string]$Sha,
    [string]$Repo = 'KseniiaSharp/sayit-words',
    [int]$TimeoutMinutes = 15,
    [int]$IntervalSeconds = 15
)

$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$root = Split-Path -Parent $PSScriptRoot
if (-not $Sha) { $Sha = (git -C $root rev-parse HEAD).Trim() }

$headers = @{ 'User-Agent' = 'sayit-words-watch'; 'Accept' = 'application/vnd.github+json' }
if ($env:GITHUB_TOKEN) { $headers['Authorization'] = 'Bearer ' + $env:GITHUB_TOKEN }

function Get-Api([string]$Url) {
    if ($Url -notlike 'https://*') { $Url = 'https://api.github.com/repos/{0}/{1}' -f $Repo, $Url }
    Invoke-RestMethod -Uri $Url -Headers $headers
}

$deadline = (Get-Date).AddMinutes($TimeoutMinutes)
Write-Output ('Waiting for GitHub Actions on {0} commit {1} ...' -f $Repo, $Sha.Substring(0, 7))

$last = ''
while ($true) {
    $runs = @((Get-Api ('actions/runs?head_sha={0}&per_page=20' -f $Sha)).workflow_runs)
    if ($runs.Count -gt 0) {
        $state = ($runs | ForEach-Object { '{0} [{1}]: {2}' -f $_.name, $_.event, $_.status }) -join '; '
        if ($state -ne $last) { Write-Output ('{0:HH:mm:ss} {1}' -f (Get-Date), $state); $last = $state }
        if (-not ($runs | Where-Object { $_.status -ne 'completed' })) { break }
    }
    if ((Get-Date) -gt $deadline) {
        if ($runs.Count -eq 0) { Write-Output 'Timed out: no workflow run started for this commit.' }
        else { Write-Output 'Timed out: a workflow run is still in progress.' }
        exit 2
    }
    Start-Sleep -Seconds $IntervalSeconds
}

$failed = 0
foreach ($run in $runs) {
    Write-Output ''
    Write-Output ('{0} ({1}): {2}' -f $run.name, $run.event, "$($run.conclusion)".ToUpper())
    Write-Output ('  {0}' -f $run.html_url)
    if ($run.conclusion -ne 'success') { $failed++ }

    foreach ($job in @((Get-Api ('actions/runs/{0}/jobs' -f $run.id)).jobs)) {
        Write-Output ('  job {0}: {1}' -f $job.name, $job.conclusion)
        foreach ($step in @($job.steps)) { Write-Output ('    {0,-9} {1}' -f $step.conclusion, $step.name) }
        foreach ($note in @(Get-Api ($job.check_run_url + '/annotations'))) {
            if ($note) { Write-Output ('    {0}: {1}:{2} {3}' -f $note.annotation_level, $note.path, $note.start_line, $note.message) }
        }
    }
}

Write-Output ''
if ($failed -gt 0) { Write-Output ('RESULT: FAILED ({0} of {1} runs)' -f $failed, $runs.Count); exit 1 }
Write-Output ('RESULT: SUCCESS ({0} runs)' -f $runs.Count)
exit 0
