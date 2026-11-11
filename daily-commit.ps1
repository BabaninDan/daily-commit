# Adds "date time - funny word" to daily-log.md, commits it and pushes (if a remote is set).
# Runs automatically at Windows logon (shortcut in the Startup folder).

$ErrorActionPreference = 'Stop'
$env:GIT_TERMINAL_PROMPT = '0'   # never hang waiting for a password

$repo      = $PSScriptRoot
$logFile   = Join-Path $repo 'daily-log.md'
$wordsFile = Join-Path $repo 'words.txt'
$runLog    = Join-Path $repo 'run.log'      # local diagnostics, ignored by git
$utf8      = New-Object System.Text.UTF8Encoding($false)

function Write-RunLog($msg) {
    [IO.File]::AppendAllText($runLog, "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')  $msg`r`n", $utf8)
}

function Invoke-Git {
    $ErrorActionPreference = 'Continue'   # git writes progress to stderr; don't treat it as an error
    & $git -C $repo @args 2>&1 | ForEach-Object { "$_" }
    if ($LASTEXITCODE -ne 0) { throw "git $($args -join ' ') failed (exit $LASTEXITCODE)" }
}

try {
    $git = (Get-Command git -ErrorAction SilentlyContinue).Source
    if (-not $git) { $git = 'C:\Program Files\Git\cmd\git.exe' }

    $words = [IO.File]::ReadAllLines($wordsFile, $utf8) | Where-Object { $_.Trim() }
    $word  = ($words | Get-Random).Trim()
    $stamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $line  = "- $stamp - $word"

    [IO.File]::AppendAllText($logFile, "$line`r`n", $utf8)

    Invoke-Git add daily-log.md | Out-Null
    Invoke-Git commit -m "$stamp - $word" | Out-Null
    Write-RunLog "committed: $line"

    # Push only if a remote exists. Network may not be up right after boot, so retry.
    if (Invoke-Git remote) {
        $pushed = $false
        for ($i = 1; $i -le 10 -and -not $pushed; $i++) {
            try {
                Invoke-Git push -u origin HEAD | Out-Null
                $pushed = $true
                Write-RunLog "pushed (attempt $i)"
            } catch {
                Start-Sleep -Seconds 30
            }
        }
        if (-not $pushed) { Write-RunLog "push failed - will be pushed next time" }
    }
} catch {
    Write-RunLog "ERROR: $_"
    exit 1
}
