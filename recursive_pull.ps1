# Recursive Git Repository Pull - PowerShell
param(
    [string]$RootPath = ".",
    [ValidateSet("pull", "fetch", "rebase", "merge", "stash-pull")]
    [string]$PullType = "pull",
    [int]$MaxDepth = 10,
    [switch]$AutoStash = $true,
    [switch]$Force = $false
)

function Pull-GitRepository {
    param([string]$RepoPath, [string]$Type, [bool]$Stash, [bool]$ForceMode)
    
    Push-Location $RepoPath
    try {
        Write-Host "  [PULL] Processing: $RepoPath" -ForegroundColor Yellow
        
        # Check if we have a remote configured
        $remotes = git remote 2>$null
        if (-not $remotes) {
            Write-Host "    [SKIP] No remotes configured" -ForegroundColor Yellow
            return
        }
        
        # Get current branch
        $currentBranch = git symbolic-ref --short HEAD 2>$null
        if (-not $currentBranch) {
            Write-Host "    [SKIP] Detached HEAD state" -ForegroundColor Yellow
            return
        }
        
        # Check for upstream branch
        $upstream = git rev-parse --abbrev-ref "@{upstream}" 2>$null
        if (-not $upstream -and -not $ForceMode) {
            Write-Host "    [SKIP] No upstream branch configured for $currentBranch" -ForegroundColor Yellow
            return
        }
        
        # Check for uncommitted changes
        $hasChanges = git status --porcelain 2>$null
        $stashCreated = $false
        
        if ($hasChanges -and $Stash) {
            Write-Host "    [STASH] Saving uncommitted changes..." -ForegroundColor Blue
            $stashResult = git stash push -m "Auto-stash before pull $(Get-Date)" 2>$null
            if ($LASTEXITCODE -eq 0) {
                $stashCreated = $true
                Write-Host "    [STASH] Changes saved successfully" -ForegroundColor Blue
            } else {
                Write-Host "    [ERROR] Failed to stash changes" -ForegroundColor Red
                return
            }
        } elseif ($hasChanges -and -not $Stash) {
            Write-Host "    [SKIP] Uncommitted changes present (use -AutoStash to handle)" -ForegroundColor Yellow
            return
        }
        
        # Perform the git operation based on type
        $success = $false
        switch ($Type) {
            "pull" {
                Write-Host "    [PULL] Pulling from remote..." -ForegroundColor Cyan
                git pull 2>$null
                $success = ($LASTEXITCODE -eq 0)
            }
            "fetch" {
                Write-Host "    [FETCH] Fetching from remote..." -ForegroundColor Cyan
                git fetch --all 2>$null
                $success = ($LASTEXITCODE -eq 0)
                if ($success) {
                    Write-Host "    [INFO] Fetch complete - no merge performed" -ForegroundColor Green
                }
            }
            "rebase" {
                Write-Host "    [REBASE] Rebasing on remote..." -ForegroundColor Cyan
                git pull --rebase 2>$null
                $success = ($LASTEXITCODE -eq 0)
            }
            "merge" {
                Write-Host "    [MERGE] Merging from remote..." -ForegroundColor Cyan
                git pull --no-rebase 2>$null
                $success = ($LASTEXITCODE -eq 0)
            }
            "stash-pull" {
                Write-Host "    [STASH-PULL] Force stash and pull..." -ForegroundColor Cyan
                if ($hasChanges) {
                    git stash push -m "Force stash $(Get-Date)" 2>$null
                    $stashCreated = $true
                }
                git pull 2>$null
                $success = ($LASTEXITCODE -eq 0)
            }
        }
        
        if ($success) {
            Write-Host "    [SUCCESS] Operation completed successfully" -ForegroundColor Green
            
            # Restore stashed changes if we created a stash
            if ($stashCreated -and $Type -ne "stash-pull") {
                Write-Host "    [RESTORE] Restoring stashed changes..." -ForegroundColor Blue
                $popResult = git stash pop 2>$null
                if ($LASTEXITCODE -eq 0) {
                    Write-Host "    [RESTORE] Changes restored successfully" -ForegroundColor Blue
                } else {
                    Write-Host "    [WARNING] Could not restore stash - may have conflicts" -ForegroundColor Yellow
                    Write-Host "    [INFO] Use 'git stash list' and 'git stash pop' manually" -ForegroundColor Cyan
                }
            }
        } else {
            Write-Host "    [ERROR] Operation failed" -ForegroundColor Red
            # If we stashed but pull failed, offer to restore
            if ($stashCreated) {
                Write-Host "    [INFO] Stashed changes preserved - use 'git stash pop' to restore" -ForegroundColor Cyan
            }
        }
        
    }
    catch {
        Write-Host "    [ERROR] Exception: $($_.Exception.Message)" -ForegroundColor Red
    }
    finally {
        Pop-Location
    }
}
function Find-GitRepositories {
    param([string]$Path, [int]$CurrentDepth = 0)
    
    if ($CurrentDepth -gt $MaxDepth) {
        Write-Host "[WARNING] Max depth reached at: $Path" -ForegroundColor Yellow
        return
    }
    
    # Check if current directory is a git repo
    if (Test-Path (Join-Path $Path ".git")) {
        Write-Host "[FOUND] Git repository: $Path" -ForegroundColor Cyan
        Pull-GitRepository -RepoPath $Path -Type $PullType -Stash $AutoStash -ForceMode $Force
        return  # Don't recurse into subdirectories of git repos
    }
    
    # Recurse into subdirectories
    try {
        Get-ChildItem -Path $Path -Directory -Force -ErrorAction SilentlyContinue | ForEach-Object {
            Find-GitRepositories -Path $_.FullName -CurrentDepth ($CurrentDepth + 1)
        }
    }
    catch {
        Write-Host "[WARNING] Cannot access: $Path" -ForegroundColor Yellow
    }
}

function Show-Summary {
    Write-Host ""
    Write-Host "=== PULL SCRIPT USAGE ===" -ForegroundColor Cyan
    Write-Host "Pull types:" -ForegroundColor White
    Write-Host "  pull        - Standard git pull (default)" -ForegroundColor Gray
    Write-Host "  fetch       - Fetch only, no merge" -ForegroundColor Gray
    Write-Host "  rebase      - Pull with rebase" -ForegroundColor Gray
    Write-Host "  merge       - Pull with explicit merge" -ForegroundColor Gray
    Write-Host "  stash-pull  - Force stash and pull (leaves stash)" -ForegroundColor Gray
    Write-Host ""
    Write-Host "Examples:" -ForegroundColor White
    Write-Host "  .\recursive_pull.ps1                    # Standard pull all repos" -ForegroundColor Gray
    Write-Host "  .\recursive_pull.ps1 -PullType rebase   # Rebase all repos" -ForegroundColor Gray
    Write-Host "  .\recursive_pull.ps1 -AutoStash:$false   # Don't auto-stash changes" -ForegroundColor Gray
    Write-Host "  .\recursive_pull.ps1 -Force             # Pull repos without upstream" -ForegroundColor Gray
    Write-Host "=========================" -ForegroundColor Cyan
}

# Main execution
Write-Host "[START] Recursively pulling git repositories..." -ForegroundColor Cyan
Write-Host "Root path: $RootPath" -ForegroundColor Cyan
Write-Host "Pull type: $PullType" -ForegroundColor Cyan
Write-Host "Auto-stash: $AutoStash" -ForegroundColor Cyan
Write-Host "Force mode: $Force" -ForegroundColor Cyan
Write-Host "Max depth: $MaxDepth" -ForegroundColor Cyan
Write-Host "=================================================" -ForegroundColor Gray

$FullPath = (Resolve-Path $RootPath).Path
Find-GitRepositories -Path $FullPath

Write-Host ""
Write-Host "[COMPLETE] Recursive pull finished!" -ForegroundColor Green
Show-Summary