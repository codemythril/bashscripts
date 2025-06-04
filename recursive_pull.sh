#!/bin/bash

# Optimized Recursive Git Pull & Rebase - Only Git Repositories
# Usage: ./git_pull_rebase.sh [root_path] [operation]

ROOT_PATH="${1:-.}"
OPERATION="${2:-rebase}"
MAX_DEPTH="${3:-20}"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
GRAY='\033[0;37m'
NC='\033[0m'

# Counters for summary
TOTAL_REPOS=0
SUCCESS_COUNT=0
SKIP_COUNT=0
ERROR_COUNT=0

echo -e "${CYAN}=== Git Repository Pull & Rebase Tool ===${NC}"
echo -e "${CYAN}Root path: $ROOT_PATH${NC}"
echo -e "${CYAN}Operation: $OPERATION${NC}"
echo -e "${CYAN}Max depth: $MAX_DEPTH${NC}"
echo "============================================="

# Function to process a single git repository
process_git_repo() {
    local repo_path="$1"
    local operation="$2"
    
    echo -e "${YELLOW}📂 Processing: $repo_path${NC}"
    
    # Change to repository directory
    cd "$repo_path" || {
        echo -e "  ${RED}❌ Cannot access directory${NC}"
        ((ERROR_COUNT++))
        return 1
    }
    
    # Verify it's actually a git repository
    if ! git rev-parse --git-dir &>/dev/null; then
        echo -e "  ${GRAY}⏭️  Not a valid git repository${NC}"
        ((SKIP_COUNT++))
        return 0
    fi
    
    # Check if repo has remotes
    if ! git remote show &>/dev/null; then
        echo -e "  ${GRAY}⏭️  No remotes configured${NC}"
        ((SKIP_COUNT++))
        return 0
    fi
    
    # Get current branch
    local current_branch
    current_branch=$(git symbolic-ref --short HEAD 2>/dev/null)
    if [ -z "$current_branch" ]; then
        echo -e "  ${GRAY}⏭️  Detached HEAD state${NC}"
        ((SKIP_COUNT++))
        return 0
    fi
    
    # Check for upstream branch
    local upstream
    upstream=$(git rev-parse --abbrev-ref "@{upstream}" 2>/dev/null)
    if [ -z "$upstream" ]; then
        echo -e "  ${GRAY}⏭️  No upstream branch for '$current_branch'${NC}"
        ((SKIP_COUNT++))
        return 0
    fi
    
    # Show current status
    local behind_ahead
    behind_ahead=$(git rev-list --left-right --count @{upstream}...HEAD 2>/dev/null)
    if [ -n "$behind_ahead" ]; then
        local behind=$(echo "$behind_ahead" | cut -f1)
        local ahead=$(echo "$behind_ahead" | cut -f2)
        if [ "$behind" -gt 0 ] || [ "$ahead" -gt 0 ]; then
            echo -e "  ${BLUE}ℹ️  Status: $ahead ahead, $behind behind${NC}"
        fi
    fi
    
    # Handle uncommitted changes
    local has_changes
    has_changes=$(git status --porcelain 2>/dev/null)
    local stash_created=false
    
    if [ -n "$has_changes" ]; then
        echo -e "  ${BLUE}💾 Stashing uncommitted changes...${NC}"
        if git stash push -m "Auto-stash before $operation $(date '+%Y-%m-%d %H:%M:%S')" &>/dev/null; then
            stash_created=true
            echo -e "  ${BLUE}✅ Changes stashed successfully${NC}"
        else
            echo -e "  ${RED}❌ Failed to stash changes${NC}"
            ((ERROR_COUNT++))
            return 1
        fi
    fi
    
    # Perform the git operation
    local success=false
    case "$operation" in
        "rebase")
            echo -e "  ${CYAN}🔄 Rebasing on upstream...${NC}"
            if git pull --rebase --autostash 2>/dev/null; then
                success=true
            fi
            ;;
        "pull")
            echo -e "  ${CYAN}🔄 Pulling from upstream...${NC}"
            if git pull 2>/dev/null; then
                success=true
            fi
            ;;
        "fetch")
            echo -e "  ${CYAN}📥 Fetching from remote...${NC}"
            if git fetch --all --prune 2>/dev/null; then
                success=true
                echo -e "  ${GREEN}ℹ️  Fetch complete - no merge performed${NC}"
            fi
            ;;
        "merge")
            echo -e "  ${CYAN}🔄 Merging from upstream...${NC}"
            if git pull --no-rebase 2>/dev/null; then
                success=true
            fi
            ;;
        *)
            echo -e "  ${RED}❌ Unknown operation: $operation${NC}"
            ((ERROR_COUNT++))
            return 1
            ;;
    esac
    
    if [ "$success" = "true" ]; then
        echo -e "  ${GREEN}✅ $operation completed successfully${NC}"
        ((SUCCESS_COUNT++))
        
        # Restore stashed changes if we created a stash and it's not just a fetch
        if [ "$stash_created" = "true" ] && [ "$operation" != "fetch" ]; then
            echo -e "  ${BLUE}🔄 Restoring stashed changes...${NC}"
            if git stash pop 2>/dev/null; then
                echo -e "  ${BLUE}✅ Stashed changes restored${NC}"
            else
                echo -e "  ${YELLOW}⚠️  Could not restore stash - may have conflicts${NC}"
                echo -e "  ${GRAY}💡 Use 'git stash list' and 'git stash pop' manually${NC}"
            fi
        fi
    else
        echo -e "  ${RED}❌ $operation failed${NC}"
        ((ERROR_COUNT++))
        
        # If we stashed but operation failed, preserve the stash
        if [ "$stash_created" = "true" ]; then
            echo -e "  ${GRAY}💡 Stashed changes preserved - use 'git stash pop' to restore${NC}"
        fi
    fi
    
    echo ""  # Add spacing between repos
}

# Main function - find and process only git repositories
main() {
    echo -e "${BLUE}🔍 Searching for git repositories...${NC}"
    echo ""
    
    # Use find to locate only .git directories, then process their parent directories
    # This is much more efficient than traversing every single directory
    while IFS= read -r -d '' gitdir; do
        repo_dir=$(dirname "$gitdir")
        
        # Convert to absolute path for cleaner display
        repo_dir=$(cd "$repo_dir" 2>/dev/null && pwd)
        
        # Skip if we couldn't get the path
        [ -z "$repo_dir" ] && continue
        
        # Increment total counter
        ((TOTAL_REPOS++))
        
        # Save current directory
        local original_dir=$(pwd)
        
        # Process the repository
        process_git_repo "$repo_dir" "$OPERATION"
        
        # Return to original directory
        cd "$original_dir" || exit 1
        
    done < <(find "$ROOT_PATH" -name ".git" -type d -maxdepth "$MAX_DEPTH" -print0 2>/dev/null)
    
    # Show summary
    echo -e "${CYAN}=============================================${NC}"
    echo -e "${GREEN}📊 SUMMARY:${NC}"
    echo -e "  ${CYAN}Total repositories found: $TOTAL_REPOS${NC}"
    echo -e "  ${GREEN}Successfully processed: $SUCCESS_COUNT${NC}"
    echo -e "  ${YELLOW}Skipped: $SKIP_COUNT${NC}"
    echo -e "  ${RED}Errors: $ERROR_COUNT${NC}"
    echo ""
    
    if [ "$TOTAL_REPOS" -eq 0 ]; then
        echo -e "${YELLOW}⚠️  No git repositories found in: $ROOT_PATH${NC}"
    elif [ "$ERROR_COUNT" -eq 0 ]; then
        echo -e "${GREEN}🎉 All repositories processed successfully!${NC}"
    else
        echo -e "${YELLOW}⚠️  Some repositories had errors. Check the output above.${NC}"
    fi
}

# Show usage if help requested
if [[ "$1" == "-h" || "$1" == "--help" ]]; then
    echo "Usage: $0 [path] [operation] [max_depth]"
    echo ""
    echo "Operations:"
    echo "  rebase  - git pull --rebase (default, recommended)"
    echo "  pull    - git pull (standard merge)"
    echo "  fetch   - git fetch --all --prune (safe, no merge)"
    echo "  merge   - git pull --no-rebase (explicit merge)"
    echo ""
    echo "Examples:"
    echo "  $0                          # Rebase all git repos in current directory"
    echo "  $0 /home/user/projects      # Rebase all repos in specific path"
    echo "  $0 . fetch                  # Fetch all repos (safe)"
    echo "  $0 . pull 10                # Pull with max depth 10"
    echo ""
    echo "This script ONLY processes actual git repositories, skipping all other folders."
    exit 0
fi

# Validate root path
if [ ! -d "$ROOT_PATH" ]; then
    echo -e "${RED}❌ Error: Directory does not exist: $ROOT_PATH${NC}"
    exit 1
fi

# Convert to absolute path
ROOT_PATH=$(cd "$ROOT_PATH" 2>/dev/null && pwd)

# Run main function
main

# Exit with appropriate code
if [ "$ERROR_COUNT" -gt 0 ]; then
    exit 1
else
    exit 0
fi