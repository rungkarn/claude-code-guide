# Install programs and restore Claude Code on the NEW computer.
# Usage:  powershell -ExecutionPolicy Bypass -File .\setup-new-pc.ps1 -Backup <folder> [-OldRoot <path> -NewRoot <path>]
#   -Backup   the claude-migration folder made by backup-old-pc.ps1
#   -OldRoot / -NewRoot   only if your project folder moved, e.g.
#             -OldRoot "D:\oneDrive\OneDrive - NSTDA" -NewRoot "C:\Users\me\OneDrive - NSTDA"

param(
    [Parameter(Mandatory = $true)][string]$Backup,
    [string]$OldRoot,
    [string]$NewRoot,
    [switch]$SkipInstall
)

if (-not (Test-Path $Backup)) { Write-Error "Backup folder not found: $Backup"; exit 1 }

# 1. Programs
if (-not $SkipInstall) {
    $apps = @(
        "Git.Git",                    # required by Claude Code on Windows (Git Bash)
        "GitHub.cli",                 # gh: PRs, GitHub Pages
        "Microsoft.VisualStudioCode", # editor
        "CondaForge.Miniforge3",      # Python + conda/mamba envs (conda-forge)
        "OpenJS.NodeJS.LTS",          # npx, used by many MCP servers
        "Anthropic.Claude"            # Claude desktop app
    )
    foreach ($id in $apps) {
        Write-Host "Installing $id ..."
        winget install --id $id -e --source winget --accept-package-agreements --accept-source-agreements
    }

    Write-Host "Installing Claude Code CLI ..."
    Invoke-RestMethod https://claude.ai/install.ps1 | Invoke-Expression
}

# 2. Restore ~/.claude (memory, settings, skills, agents, transcripts)
$claudeDir = Join-Path $env:USERPROFILE ".claude"
$src = Join-Path $Backup "dot-claude"
if (Test-Path $src) {
    robocopy $src $claudeDir /E /R:1 /W:1 /NFL /NDL /NP | Out-Null
    Write-Host "[ok] restored ~/.claude"
}
$cj = Join-Path $Backup "claude.json"
if (Test-Path $cj) {
    Copy-Item $cj (Join-Path $env:USERPROFILE ".claude.json") -Force
    Write-Host "[ok] restored ~/.claude.json"
}
$dc = Join-Path $Backup "claude_desktop_config.json"
if (Test-Path $dc) {
    New-Item -ItemType Directory -Force -Path (Join-Path $env:APPDATA "Claude") | Out-Null
    Copy-Item $dc (Join-Path $env:APPDATA "Claude\claude_desktop_config.json") -Force
    Write-Host "[ok] restored claude_desktop_config.json"
}

# 3. Project folder moved? Rename memory/transcript folders to match the new path.
#    Claude names them after the project path with every non-letter/digit turned into "-".
if ($OldRoot -and $NewRoot) {
    $oldSlug = ($OldRoot.TrimEnd('\') -replace '[^A-Za-z0-9]', '-')
    $newSlug = ($NewRoot.TrimEnd('\') -replace '[^A-Za-z0-9]', '-')
    $projects = Join-Path $claudeDir "projects"
    Get-ChildItem $projects -Directory | Where-Object { $_.Name.StartsWith($oldSlug, [StringComparison]::OrdinalIgnoreCase) } | ForEach-Object {
        $target = $newSlug + $_.Name.Substring($oldSlug.Length)
        if (-not (Test-Path (Join-Path $projects $target))) {
            Rename-Item $_.FullName $target
            Write-Host "[ok] $($_.Name) -> $target"
        }
    }
}

# Refresh PATH so newly installed tools work in this window
$env:Path = [Environment]::GetEnvironmentVariable("Path", "Machine") + ";" + [Environment]::GetEnvironmentVariable("Path", "User")

# 4. Git identity
$gc = Join-Path $Backup "git-config.txt"
if ((Test-Path $gc) -and (Get-Command git -ErrorAction SilentlyContinue)) {
    foreach ($line in Get-Content $gc) {
        if ($line -match '^user\.(name|email)=(.+)$') { git config --global "user.$($Matches[1])" $Matches[2] }
    }
    Write-Host "[ok] git user.name / user.email"
}

# 5. VS Code extensions
$ve = Join-Path $Backup "vscode-extensions.txt"
if ((Test-Path $ve) -and (Get-Command code -ErrorAction SilentlyContinue)) {
    foreach ($ext in Get-Content $ve) { if ($ext) { code --install-extension $ext --force | Out-Null } }
    Write-Host "[ok] VS Code extensions"
}

# 6. Conda environments (Miniforge)
$conda = (Get-Command conda -ErrorAction SilentlyContinue).Source
foreach ($p in "$env:USERPROFILE\miniforge3", "$env:LOCALAPPDATA\miniforge3", "C:\ProgramData\miniforge3") {
    if (-not $conda -and (Test-Path "$p\Scripts\conda.exe")) { $conda = "$p\Scripts\conda.exe" }
}
$rc = Join-Path $Backup "condarc"
if (Test-Path $rc) { Copy-Item $rc (Join-Path $env:USERPROFILE ".condarc") -Force; Write-Host "[ok] restored .condarc" }
$envDir = Join-Path $Backup "conda-envs"
if ($conda) {
    & $conda init powershell | Out-Null   # lets "conda activate" work in new PowerShell windows
    $mamba = Join-Path (Split-Path $conda -Parent) "mamba.exe"
    $tool = $conda
    if (Test-Path $mamba) { $tool = $mamba }   # mamba solves much faster
    if (Test-Path $envDir) {
        Get-ChildItem $envDir -Filter *.yml | Where-Object { $_.BaseName -notlike "base*" } | ForEach-Object {
            Write-Host "Creating conda env $($_.BaseName) ..."
            & $tool env create -n $_.BaseName -f $_.FullName
            if ($LASTEXITCODE -ne 0) { Write-Warning "Could not create $($_.BaseName); fix its .yml and run: mamba env create -n $($_.BaseName) -f $($_.FullName)" }
        }
    }
} else {
    Write-Warning "conda not found. Open a new PowerShell window and run this script again with -SkipInstall."
}

Write-Host ""
Write-Host "Done. Still to do by hand:"
Write-Host "  1. Sign in to OneDrive and let your project folders sync"
Write-Host "  2. Open the Claude app and sign in"
Write-Host "  3. Run: gh auth login"
Write-Host "  4. Run: claude   (sign in once in the terminal)"
