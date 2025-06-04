# Simple Recursive Git Pull Script
param(
    [string]$Path = ".",
    [ValidateSet("pull", "fetch", "rebase")]
    [string]$Type = "pull",
    [switch]$AutoStash = $true
)

Write-Host "Pulling all git repositories recursively in: $Path" -ForegroundColor Cyan
Write-Host "Type: $Type | Auto-stash: $AutoStash" -ForegroundColor Cyan
Write-Host "================================================" -ForegroundColor Gray

Get-ChildItem -Path $Path -Filter ".git" -Recurse -Force -Directory | ForEach-Object {
    $repoPath = $_.Parent.FullName
    Write-Host "> Processing: $repoPath" -ForegroundColor Yellow
    
    Push-Location $repoPath
    try {
        # Check if repo has remotes
        $remotes = git remote 2>$null
        if (-not $remotes) {
            Write-Host "  [SKIP] No remotes configured" -ForegroundColor Gray
            Pop-Location
            return
        }
        
        # Handle uncommitted changes
        $hasChanges = git status --porcelain 2>$null
        $stashed = $false
        
        if ($hasChanges -and $AutoStash) {
            Write-Host "  [STASH] Saving changes..." -ForegroundColor Blue
            git stash push -m "Auto-stash $(Get-Date)" 2>$null
            if ($LASTEXITCODE -eq 0) { $stashed = $true }
        }
        
        # Perform git operation
        switch ($Type) {
            "pull"   { git pull 2>$null }
            "fetch"  { git fetch --all 2>$null }
            "rebase" { git pull --rebase 2>$null }
        }
        
        if ($LASTEXITCODE -eq 0) {
            Write-Host "  [SUCCESS] $Type completed" -ForegroundColor Green
            
            # Restore stash if created
            if ($stashed -and $Type -ne "fetch") {
                git stash pop 2>$null
                if ($LASTEXITCODE -eq 0) {
                    Write-Host "  [RESTORE] Changes restored" -ForegroundColor Blue
                } else {
                    Write-Host "  [WARNING] Check stash manually" -ForegroundColor Yellow
                }
            }
        } else {
            Write-Host "  [ERROR] $Type failed" -ForegroundColor Red
        }
    }
    catch {
        Write-Host "  [ERROR] $($_.Exception.Message)" -ForegroundColor Red
    }
    Pop-Location
}

Write-Host ""
Write-Host "[DONE] All repositories processed!" -ForegroundColor Green