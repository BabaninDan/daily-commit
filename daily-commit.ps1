# Adds "date time - funny word" to daily-log.md, commits it and pushes (if a remote is set).
# Runs from the Task Scheduler task "daily-commit" at logon and wake from sleep.
# Makes a new entry on every launch (runs within 5 minutes of the last entry only push).

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

# Logon and wake can fire together - let only one copy run.
$mutex = New-Object System.Threading.Mutex($false, 'Local\daily-commit')
if (-not $mutex.WaitOne(0)) { exit 0 }

try {
    $git = (Get-Command git -ErrorAction SilentlyContinue).Source
    if (-not $git) { $git = 'C:\Program Files\Git\cmd\git.exe' }

    # One commit per launch. Logon and wake can both fire for the same launch,
    # so skip if the last entry is less than 5 minutes old.
    $recent = $false
    if (Test-Path $logFile) {
        $last = [IO.File]::ReadAllLines($logFile, $utf8) | Where-Object { $_ -match '^- \d{4}-' } | Select-Object -Last 1
        if ($last -and $last.Length -ge 21) {
            $lastTime = [datetime]::ParseExact($last.Substring(2, 19), 'yyyy-MM-dd HH:mm:ss', $null)
            $recent = ((Get-Date) - $lastTime).TotalMinutes -lt 5
        }
    }

    if (-not $recent) {
        $words = [IO.File]::ReadAllLines($wordsFile, $utf8) | Where-Object { $_.Trim() }
        $word  = ($words | Get-Random).Trim()
        $stamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
        $line  = "- $stamp - $word"

        [IO.File]::AppendAllText($logFile, "$line`r`n", $utf8)

        Invoke-Git add daily-log.md | Out-Null
        Invoke-Git commit -m "$stamp - $word" | Out-Null
        Write-RunLog "committed: $line"
    }

    # Anything left to push? (also catches pushes that failed earlier)
    $hasRemote = [bool](Invoke-Git remote)
    $unpushed  = $true
    if ($hasRemote) {
        try { $unpushed = [int](Invoke-Git rev-list --count '@{u}..HEAD') -gt 0 } catch { $unpushed = $true }
    }

    # Push only if a remote exists. Network may not be up right after wake, so retry.
    if ($hasRemote -and $unpushed) {
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
} finally {
    $mutex.ReleaseMutex()
}
