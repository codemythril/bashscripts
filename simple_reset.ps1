# Simple Recursive Git Reset
param([string]$Path = ".", [string]$Type = "hard")

Write-Host "Resetting all git repositories recursively in: $Path"

Get-ChildItem -Path $Path -Filter ".git" -Recurse -Force -Directory | ForEach-Object {
    $repoPath = $_.Parent.FullName
    Write-Host "> Processing: $repoPath" -ForegroundColor Cyan
    
    Push-Location $repoPath
    try {
        switch ($Type) {
            "soft"  { git reset --soft HEAD }
            "hard"  { git reset --hard HEAD; git clean -fd }
            "pull"  { git stash; git reset --hard HEAD; git pull }
        }
        Write-Host "  SUCCESS" -ForegroundColor Green
    }
    catch {
        Write-Host "  ERROR: $($_.Exception.Message)" -ForegroundColor Red
    }
    Pop-Location
}

Write-Host "DONE - All repositories processed!" -ForegroundColor Green