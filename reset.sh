#!/bin/bash

# Recursive Git Repository Reset - Bash/Linux
# Usage: ./recursive_reset.sh [root_path] [reset_type] [max_depth]

ROOT_PATH="${1:-.}"
RESET_TYPE="${2:-hard}"
MAX_DEPTH="${3:-10}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

reset_git_repo() {
    local repo_path="$1"
    local reset_type="$2"
    
    echo -e "${YELLOW}  🔄 Resetting: $repo_path${NC}"
    
    cd "$repo_path" || return 1
    
    case "$reset_type" in
        "soft")
            git reset --soft HEAD
            ;;
        "hard")
            git reset --hard HEAD
            ;;
        "clean")
            git reset --hard HEAD
            git clean -fd
            echo -e "${BLUE}    🧹 Cleaned untracked files${NC}"
            ;;
        "pull")
            # Stash if there are changes
            if [ -n "$(git status --porcelain 2>/dev/null)" ]; then
                git stash push -m "Auto-stash $(date)"
                echo -e "${BLUE}    💾 Stashed changes${NC}"
            fi
            git reset --hard HEAD
            git pull
            echo -e "${BLUE}    ⬇️ Pulled latest changes${NC}"
            ;;
        "origin")
            # Reset to origin/main or origin/master
            if git show-ref --verify --quiet refs/remotes/origin/main 2>/dev/null; then
                branch="main"
            elif git show-ref --verify --quiet refs/remotes/origin/master 2>/dev/null; then
                branch="master"
            else
                echo -e "${YELLOW}    ⚠️ No origin/main or origin/master found${NC}"
                return 1
            fi
            
            git stash 2>/dev/null || true
            git checkout "$branch" 2>/dev/null || true
            git reset --hard "origin/$branch"
            git pull origin "$branch"
            echo -e "${BLUE}    🎯 Reset to origin/$branch${NC}"
            ;;
        *)
            echo -e "${RED}    ❌ Unknown reset type: $reset_type${NC}"
            return 1
            ;;
    esac
    
    echo -e "${GREEN}    ✅ Success${NC}"
}

find_git_repos() {
    local search_path="$1"
    local current_depth="$2"
    
    # Check depth limit
    if [ "$current_depth" -gt "$MAX_DEPTH" ]; then
        echo -e "${YELLOW}⚠️ Max depth reached at: $search_path${NC}"
        return
    fi
    
    # Check if current directory is a git repo
    if [ -d "$search_path/.git" ]; then
        echo -e "${CYAN}📂 Found git repository: $search_path${NC}"
        
        # Save current directory
        local original_dir="$(pwd)"
        
        # Reset the repository
        if reset_git_repo "$search_path" "$RESET_TYPE"; then
            echo -e "${GREEN}✅ Repository reset successfully${NC}"
        else
            echo -e "${RED}❌ Failed to reset repository${NC}"
        fi
        
        # Restore original directory
        cd "$original_dir"
        
        # Don't recurse into subdirectories of git repos
        return
    fi
    
    # Recurse into subdirectories
    if [ -d "$search_path" ]; then
        find "$search_path" -maxdepth 1 -type d ! -path "$search_path" 2>/dev/null | while read -r subdir; do
            find_git_repos "$subdir" $((current_depth + 1))
        done
    fi
}

# Main execution
echo -e "${CYAN}🔍 Recursively searching for git repositories...${NC}"
echo -e "${CYAN}Root path: $ROOT_PATH${NC}"
echo -e "${CYAN}Reset type: $RESET_TYPE${NC}" 
echo -e "${CYAN}Max depth: $MAX_DEPTH${NC}"
echo "=================================================="

# Convert relative path to absolute
ROOT_PATH="$(cd "$ROOT_PATH" && pwd)"

find_git_repos "$ROOT_PATH" 0

echo -e "${GREEN}🎉 Recursive reset complete!${NC}"