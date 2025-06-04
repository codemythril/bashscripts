#!/bin/bash

# Script to reset all git repositories under a given folder
# Usage: ./reset_repos.sh [parent_folder] [reset_type]
# Reset types: soft, hard, clean, pull

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
        Write-Host "  🔄 Resetting: $RepoPath" -ForegroundColor Yellow
        
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
                Write-Host "    🧹 Cleaned untracked files" -ForegroundColor Blue
            }
            "pull" {
                # Stash if there are changes
                $status = git status --porcelain 2>$null
                if ($status) {
                    git stash push -m "Auto-stash $(Get-Date)"
                    Write-Host "    💾 Stashed changes" -ForegroundColor Blue
                }
                git reset --hard HEAD
                git pull
                Write-Host "    ⬇️ Pulled latest changes" -ForegroundColor Blue
            }
            "origin" {
                # Reset to origin/main or origin/master
                $defaultBranch = git symbolic-ref refs/remotes/origin/HEAD 2>$null
                if ($defaultBranch) {
                    $branch = $defaultBranch -replace "refs/remotes/origin/", ""
                } else {
                    # Try common default branches
                    $branch = if (git show-ref --verify --quiet refs/remotes/origin/main) { "main" } 
                              elseif (git show-ref --verify --quiet refs/remotes/origin/master) { "master" }
                              else { $null }
                }
                
                if ($branch) {
                    git stash 2>$null
                    git checkout $branch 2>$null
                    git reset --hard origin/$branch
                    git pull origin $branch
                    Write-Host "    🎯 Reset to origin/$branch" -ForegroundColor Blue
                } else {
                    Write-Host "    ⚠️ No origin branch found" -ForegroundColor Yellow
                }
            }
        }
        Write-Host "    ✅ Success" -ForegroundColor Green
    }
    catch {
        Write-Host "    ❌ Error: $($_.Exception.Message)" -ForegroundColor Red
    }
    finally {
        Pop-Location
    }
}

# Main recursive function
function Find-GitRepositories {
    param([string]$Path, [int]$CurrentDepth = 0)
    
    if ($CurrentDepth -gt $MaxDepth) {
        Write-Host "⚠️ Max depth reached at: $Path" -ForegroundColor Yellow
        return
    }
    
    # Check if current directory is a git repo
    if (Test-Path (Join-Path $Path ".git")) {
        Write-Host "📂 Found git repository: $Path" -ForegroundColor Cyan
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
        Write-Host "⚠️ Cannot access: $Path" -ForegroundColor Yellow
    }
}

# Execute
Write-Host "🔍 Recursively searching for git repositories..." -ForegroundColor Cyan
Write-Host "Root path: $RootPath" -ForegroundColor Cyan
Write-Host "Reset type: $ResetType" -ForegroundColor Cyan
Write-Host "Max depth: $MaxDepth" -ForegroundColor Cyan
Write-Host "=" * 50 -ForegroundColor Gray

Find-GitRepositories -Path (Resolve-Path $RootPath).Path

Write-Host "🎉 Recursive reset complete!" -ForegroundColor Green