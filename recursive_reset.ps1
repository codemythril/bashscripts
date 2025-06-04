# Recursive Git Repository Reset - PowerShell
param(
    [string]$RootPath = ".",
    [ValidateSet("soft", "hard", "clean", "pull", "origin")]
    [string]$ResetType = "hard",
    [int]$MaxDepth = 10
)

function Reset-GitRepository {
    param([string]$RepoPath, [string]$Type)
    
    Push-Location $RepoPath
    try {
        Write-Host "  [RESET] Processing: $RepoPath" -ForegroundColor Yellow
        
        switch ($Type) {
            "soft" {
                git reset --soft HEAD
            }
            "hard" {
                git reset --hard HEAD
            }
            "clean" {
                git reset --hard HEAD
                git clean -fd
                Write-Host "    [CLEAN] Removed untracked files" -ForegroundColor Blue
            }
            "pull" {
                $status = git status --porcelain 2>$null
                if ($status) {
                    git stash push -m "Auto-stash $(Get-Date)"
                    Write-Host "    [STASH] Saved changes" -ForegroundColor Blue
                }
                git reset --hard HEAD
                git pull
                Write-Host "    [PULL] Updated from remote" -ForegroundColor Blue
            }
            "origin" {
                $branch = $null
                if (git show-ref --verify --quiet refs/remotes/origin/main 2>$null) { 
                    $branch = "main" 
                } elseif (git show-ref --verify --quiet refs/remotes/origin/master 2>$null) { 
                    $branch = "master" 
                }
                
                if ($branch) {
                    git stash 2>$null
                    git checkout $branch 2>$null
                    git reset --hard "origin/$branch"
                    git pull origin $branch
                    Write-Host "    [ORIGIN] Reset to origin/$branch" -ForegroundColor Blue
                } else {
                    Write-Host "    [WARNING] No origin branch found" -ForegroundColor Yellow
                }
            }
        }
        Write-Host "    [SUCCESS] Repository reset complete" -ForegroundColor Green
    }
    catch {
        Write-Host "    [ERROR] $($_.Exception.Message)" -ForegroundColor Red
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
        Reset-GitRepository -RepoPath $Path -Type $ResetType
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

# Main execution
Write-Host "[START] Recursively searching for git repositories..." -ForegroundColor Cyan
Write-Host "Root path: $RootPath" -ForegroundColor Cyan
Write-Host "Reset type: $ResetType" -ForegroundColor Cyan
Write-Host "Max depth: $MaxDepth" -ForegroundColor Cyan
Write-Host "=================================================" -ForegroundColor Gray

$FullPath = (Resolve-Path $RootPath).Path
Find-GitRepositories -Path $FullPath

Write-Host "[COMPLETE] Recursive reset finished!" -ForegroundColor Green