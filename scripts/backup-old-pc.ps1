# Back up Claude Code settings, memory, history and the app list on the OLD computer.
# Usage:  powershell -ExecutionPolicy Bypass -File .\backup-old-pc.ps1 [-Dest <folder>]
# The backup is private data (chat transcripts, memory). Keep it on OneDrive or a USB drive.
# Never commit it to a public GitHub repo.

param([string]$Dest)

if (-not $Dest) {
    $root = $env:OneDriveCommercial
    if (-not $root) { $root = $env:OneDrive }
    if (-not $root) { $root = [Environment]::GetFolderPath("Desktop") }
    $Dest = Join-Path $root "claude-migration"
}
New-Item -ItemType Directory -Force -Path $Dest | Out-Null
Write-Host "Backing up to $Dest"

# 1. ~/.claude (settings, CLAUDE.md, skills, agents, plugins, memory, transcripts)
#    Skip the login token and caches that are rebuilt automatically.
$claudeDir = Join-Path $env:USERPROFILE ".claude"
if (Test-Path $claudeDir) {
    robocopy $claudeDir (Join-Path $Dest "dot-claude") /E /R:1 /W:1 /NFL /NDL /NP `
        /XF .credentials.json `
        /XD cache debug telemetry shell-snapshots session-env downloads | Out-Null
    Write-Host "[ok] ~/.claude"
}

# 2. ~/.claude.json (user-level MCP servers, per-project preferences)
$claudeJson = Join-Path $env:USERPROFILE ".claude.json"
if (Test-Path $claudeJson) {
    Copy-Item $claudeJson (Join-Path $Dest "claude.json") -Force
    Write-Host "[ok] ~/.claude.json"
}

# 3. Claude desktop app MCP config (Chat tab), if any
$desktopCfg = Join-Path $env:APPDATA "Claude\claude_desktop_config.json"
if (Test-Path $desktopCfg) {
    Copy-Item $desktopCfg (Join-Path $Dest "claude_desktop_config.json") -Force
    Write-Host "[ok] claude_desktop_config.json"
}

# 4. List of installed programs (winget)
if (Get-Command winget -ErrorAction SilentlyContinue) {
    winget export -o (Join-Path $Dest "winget-apps.json") --accept-source-agreements | Out-Null
    Write-Host "[ok] winget-apps.json"
}

# 5. Git identity
if (Get-Command git -ErrorAction SilentlyContinue) {
    git config --global --list | Out-File (Join-Path $Dest "git-config.txt") -Encoding utf8
    Write-Host "[ok] git-config.txt"
}

# 6. VS Code extensions
if (Get-Command code -ErrorAction SilentlyContinue) {
    code --list-extensions | Out-File (Join-Path $Dest "vscode-extensions.txt") -Encoding utf8
    Write-Host "[ok] vscode-extensions.txt"
}

# 7. Conda environments (Miniforge / Anaconda / Miniconda)
#    conda is often not on PATH, so also look at the installs listed in ~/.conda/environments.txt
$conda = $env:CONDA_EXE
if (-not $conda) { $conda = (Get-Command conda -ErrorAction SilentlyContinue).Source }
if (-not $conda) {
    $candidates = @("$env:USERPROFILE\miniforge3", "$env:LOCALAPPDATA\miniforge3", "C:\ProgramData\miniforge3")
    $envList = Join-Path $env:USERPROFILE ".conda\environments.txt"
    if (Test-Path $envList) { $candidates += Get-Content $envList }
    foreach ($p in $candidates) {
        if ($p -and (Test-Path "$p\Scripts\conda.exe")) { $conda = "$p\Scripts\conda.exe"; break }
    }
}
if ($conda) {
    Write-Host "Using conda at $conda"
    $condarc = Join-Path $env:USERPROFILE ".condarc"
    if (Test-Path $condarc) { Copy-Item $condarc (Join-Path $Dest "condarc") -Force; Write-Host "[ok] .condarc" }
    $envDir = Join-Path $Dest "conda-envs"
    New-Item -ItemType Directory -Force -Path $envDir | Out-Null
    $envs = (& $conda env list --json | ConvertFrom-Json).envs
    foreach ($e in $envs) {
        if (-not (Test-Path $e)) { continue }
        $name = Split-Path $e -Leaf
        # The root of an install (it has no "envs" parent) is a base env: keep it for reference only
        if ((Split-Path (Split-Path $e -Parent) -Leaf) -ne "envs") { $name = "base-$name" }
        & $conda env export -p $e --no-builds | Out-File (Join-Path $envDir "$name.yml") -Encoding utf8
        Write-Host "[ok] conda env $name"
    }
}

# 8. Where things lived on this computer (needed if paths change)
@"
computer   : $env:COMPUTERNAME
user home  : $env:USERPROFILE
onedrive   : $env:OneDriveCommercial
backup at  : $(Get-Date -Format 'yyyy-MM-dd HH:mm')
"@ | Out-File (Join-Path $Dest "source-info.txt") -Encoding utf8

Write-Host ""
Write-Host "Done. Wait for OneDrive to finish syncing before you switch computers."
