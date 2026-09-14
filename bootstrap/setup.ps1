<#
.SYNOPSIS
    Development environment for the Windows VM.

.DESCRIPTION
    Run once automatically at first boot by user-data, and safe to run again by
    hand after pulling a change:

        cd C:\setup; git pull; pwsh -File .\bootstrap\setup.ps1

    Every step is idempotent. Nothing here may fail in a way that costs you SSH
    access, which is why SSH is configured in user-data and not in this file.
#>

[CmdletBinding()]
param(
    # Skip the Chocolatey packages when you only want the configuration steps.
    [switch] $SkipPackages
)

$ErrorActionPreference = 'Stop'
$ProgressPreference    = 'SilentlyContinue'

$Choco     = 'C:\ProgramData\chocolatey\bin\choco.exe'
$GitBash   = 'C:\Program Files\Git\bin\bash.exe'
$Workspace = 'C:\work'

# Edit this list, commit, and either rebuild the VM or re-run this script.
$Packages = @(
    'ripgrep'
    'fd'
    'jq'
    'fzf'
    'bat'
    '7zip'
    'neovim'
    'python313'
    'gh'
    'make'
)

# Globally installed npm CLIs. The coding agent lives here.
$NpmGlobals = @(
    '@anthropic-ai/claude-code'
)

function Step {
    param([string] $Name, [scriptblock] $Body)

    Write-Host ""
    Write-Host "=== $Name ===" -ForegroundColor Cyan
    try {
        & $Body
    } catch {
        Write-Host "!!! $Name failed: $_" -ForegroundColor Red
        $script:Failed += $Name
    }
}

$script:Failed = @()

# ---------------------------------------------------------------------------
Step 'workspace' {
    New-Item -ItemType Directory -Force -Path $Workspace | Out-Null
}

# ---------------------------------------------------------------------------
Step 'long-paths' {
    # Node and Git both trip over the 260 character limit on Windows, and npm
    # dependency trees reach it routinely.
    Set-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\FileSystem' `
        -Name 'LongPathsEnabled' -Value 1 -Type DWord
}

# ---------------------------------------------------------------------------
Step 'defender-exclusions' {
    # Real-time scanning of a node_modules tree or a build output directory is
    # the single largest source of slowness on a Windows build box. These paths
    # hold code you put there deliberately, so the trade is worth making.
    $exclude = @(
        $Workspace
        'C:\ProgramData\chocolatey'
        "$env:USERPROFILE\.npm"
        "$env:APPDATA\npm"
    )
    foreach ($path in $exclude) {
        Add-MpPreference -ExclusionPath $path -ErrorAction SilentlyContinue
    }
    foreach ($proc in @('node.exe', 'git.exe', 'pwsh.exe', 'bash.exe')) {
        Add-MpPreference -ExclusionProcess $proc -ErrorAction SilentlyContinue
    }
}

# ---------------------------------------------------------------------------
if (-not $SkipPackages) {
    Step 'packages' {
        & $Choco install -y --no-progress --limit-output @Packages
        if ($LASTEXITCODE -notin @(0, 1641, 3010)) {
            throw "chocolatey exited with $LASTEXITCODE"
        }
    }
}

# ---------------------------------------------------------------------------
Step 'machine-path' {
    # Git ships the GNU userland at usr\bin. Having it on PATH is what makes the
    # shell feel like a normal development machine.
    $extra = @(
        'C:\Program Files\Git\cmd'
        'C:\Program Files\Git\usr\bin'
        'C:\Program Files\nodejs'
        "$env:APPDATA\npm"
    )

    $current = [Environment]::GetEnvironmentVariable('Path', 'Machine')
    $parts   = $current -split ';' | Where-Object { $_ -ne '' }

    foreach ($dir in $extra) {
        if ($parts -notcontains $dir) { $parts += $dir }
    }

    [Environment]::SetEnvironmentVariable('Path', ($parts -join ';'), 'Machine')
    $env:Path = ($parts -join ';')
}

# ---------------------------------------------------------------------------
Step 'claude-code-git-bash' {
    # Claude Code runs on Windows natively but shells out to Git Bash, and it
    # will not start until it knows where that is.
    if (-not (Test-Path $GitBash)) { throw "Git Bash not found at $GitBash" }
    [Environment]::SetEnvironmentVariable('CLAUDE_CODE_GIT_BASH_PATH', $GitBash, 'Machine')
    $env:CLAUDE_CODE_GIT_BASH_PATH = $GitBash
}

# ---------------------------------------------------------------------------
if (-not $SkipPackages) {
    Step 'npm-globals' {
        $npm = 'C:\Program Files\nodejs\npm.cmd'
        if (-not (Test-Path $npm)) { throw "npm not found at $npm" }

        foreach ($pkg in $NpmGlobals) {
            & $npm install -g $pkg
            if ($LASTEXITCODE -ne 0) { throw "npm install -g $pkg exited with $LASTEXITCODE" }
        }
    }
}

# ---------------------------------------------------------------------------
Step 'git-defaults' {
    $git = 'C:\Program Files\Git\cmd\git.exe'

    # Machine-wide so they apply to every account, including SYSTEM during a
    # re-run from user-data.
    & $git config --system core.longpaths true
    & $git config --system core.autocrlf input
    & $git config --system init.defaultBranch main
    & $git config --system pull.rebase true
    & $git config --system --add safe.directory '*'
}

# ---------------------------------------------------------------------------
Step 'powershell-profile' {
    $profileDir = 'C:\Program Files\PowerShell\7'
    $profilePath = Join-Path $profileDir 'profile.ps1'
    New-Item -ItemType Directory -Force -Path $profileDir | Out-Null

    $content = @'
# Machine-wide PowerShell 7 profile, installed by bootstrap/setup.ps1.

Set-Location C:\work

$env:CLAUDE_CODE_GIT_BASH_PATH = 'C:\Program Files\Git\bin\bash.exe'

Set-Alias -Name ll -Value Get-ChildItem
Set-Alias -Name g  -Value git

function .. { Set-Location .. }

# A terminal over a long SSH link is unusable with the default PSReadLine
# prediction view, which redraws the whole line on every keystroke.
#
# The virtual terminal check is load bearing. `ssh host '<command>'` runs with
# redirected output, where setting a prediction view throws, and a profile that
# throws prints a wall of red on every single non-interactive invocation.
if ($Host.UI.SupportsVirtualTerminal -and (Get-Module -ListAvailable PSReadLine)) {
    Import-Module PSReadLine
    try {
        Set-PSReadLineOption -PredictionSource History -PredictionViewStyle InlineView
        Set-PSReadLineOption -EditMode Windows
    } catch {
        # An older PSReadLine without prediction support is not worth a warning.
    }
}

function Get-IdleShutdownState {
    $file = 'C:\ProgramData\winvm\idle-minutes.txt'
    if (Test-Path $file) { "$((Get-Content $file -Raw).Trim()) idle minutes counted" }
    else { 'watchdog has not run yet' }
}
'@

    Set-Content -Path $profilePath -Value $content -Encoding utf8 -Force
}

# ---------------------------------------------------------------------------
Write-Host ""
if ($script:Failed.Count -eq 0) {
    Write-Host 'setup complete' -ForegroundColor Green
    exit 0
}

Write-Host "setup finished with failed steps: $($script:Failed -join ', ')" -ForegroundColor Yellow
exit 1
