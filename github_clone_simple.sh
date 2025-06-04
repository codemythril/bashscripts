#!/bin/bash
# GitHub Repository Mass Cloner
# Usage: ./github_clone_all.sh [username/org] [options]

# Default configuration
CLONE_METHOD="https"  # https or ssh
TARGET_DIR="."
INCLUDE_FORKS=false
INCLUDE_PRIVATE=false
PARALLEL_JOBS=5
UPDATE_EXISTING=false
DRY_RUN=false

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
PURPLE='\033[0;35m'
GRAY='\033[0;37m'
NC='\033[0m'

# GitHub API configuration
GITHUB_API="https://api.github.com"
GITHUB_TOKEN=""
PER_PAGE=100

# Usage function
show_usage() {
    echo -e "${CYAN}=== GitHub Repository Mass Cloner ===${NC}"
    echo "Usage: $0 <username/org> [options]"
    echo ""
    echo -e "${YELLOW}Required:${NC}"
    echo "  username/org          GitHub username or organization name"
    echo ""
    echo -e "${YELLOW}Options:${NC}"
    echo "  --ssh                 Use SSH for cloning (default: HTTPS)"
    echo "  --https               Use HTTPS for cloning (default)"
    echo "  --dir <path>          Target directory (default: current)"
    echo "  --include-forks       Include forked repositories"
    echo "  --include-private     Include private repositories (requires token)"
    echo "  --token <token>       GitHub personal access token"
    echo "  --jobs <num>          Number of parallel clone jobs (default: 5)"
    echo "  --update              Update existing repositories instead of skipping"
    echo "  --dry-run             Show what would be cloned without doing it"
    echo "  --help, -h            Show this help message"
    echo ""
    echo -e "${YELLOW}Examples:${NC}"
    echo "  $0 torvalds                                    # Clone all Linus Torvalds' repos"
    echo "  $0 microsoft --dir ./microsoft-repos          # Clone to specific directory"
    echo "  $0 facebook --ssh --include-forks             # Use SSH and include forks"
    echo "  $0 myorg --token ghp_xxxx --include-private   # Include private repos"
    echo "  $0 kubernetes --jobs 10 --update              # Use 10 parallel jobs, update existing"
    echo ""
    echo -e "${YELLOW}Environment Variables:${NC}"
    echo "  GITHUB_TOKEN          GitHub personal access token"
    echo ""
    echo -e "${YELLOW}Notes:${NC}"
    echo "  • For private repositories, set GITHUB_TOKEN environment variable"
    echo "  • For organizations with many repos, consider using --jobs for faster cloning"
    echo "  • SSH cloning requires configured SSH keys"
    echo "  • Rate limit: 60 requests/hour (unauthenticated), 5000/hour (authenticated)"
}

# Parse command line arguments
parse_arguments() {
    if [ $# -eq 0 ]; then
        show_usage
        exit 1
    fi

    USERNAME="$1"
    shift

    while [[ $# -gt 0 ]]; do
        case $1 in
            --ssh)
                CLONE_METHOD="ssh"
                shift
                ;;
            --https)
                CLONE_METHOD="https"
                shift
                ;;
            --dir)
                TARGET_DIR="$2"
                shift 2
                ;;
            --include-forks)
                INCLUDE_FORKS=true
                shift
                ;;
            --include-private)
                INCLUDE_PRIVATE=true
                shift
                ;;
            --token)
                GITHUB_TOKEN="$2"
                shift 2
                ;;
            --jobs)
                PARALLEL_JOBS="$2"
                shift 2
                ;;
            --update)
                UPDATE_EXISTING=true
                shift
                ;;
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            --help|-h)
                show_usage
                exit 0
                ;;
            *)
                echo -e "${RED}❌ Unknown option: $1${NC}"
                echo "Use --help for usage information"
                exit 1
                ;;
        esac
    done

    # Check for token in environment if not provided
    if [ -z "$GITHUB_TOKEN" ] && [ -n "${GITHUB_TOKEN:-}" ]; then
        GITHUB_TOKEN="$GITHUB_TOKEN"
    fi
}

# Check dependencies
check_dependencies() {
    local missing_deps=()
    
    if ! command -v curl &> /dev/null; then
        missing_deps+=("curl")
    fi
    
    if ! command -v jq &> /dev/null; then
        missing_deps+=("jq")
    fi
    
    if ! command -v git &> /dev/null; then
        missing_deps+=("git")
    fi
    
    if [ ${#missing_deps[@]} -ne 0 ]; then
        echo -e "${RED}❌ Missing required dependencies: ${missing_deps[*]}${NC}"
        echo "Please install the missing packages and try again."
        exit 1
    fi
}

# Make authenticated API request
api_request() {
    local url="$1"
    local curl_args=()
    
    if [ -n "$GITHUB_TOKEN" ]; then
        curl_args+=("-H" "Authorization: token $GITHUB_TOKEN")
    fi
    
    curl_args+=("-H" "Accept: application/vnd.github.v3+json")
    curl_args+=("-s")
    curl_args+=("$url")
    
    curl "${curl_args[@]}"
}

# Check if user/org exists and get type
check_user_exists() {
    local username="$1"
    
    echo -e "${BLUE}🔍 Checking if '$username' exists on GitHub...${NC}"
    
    local response
    response=$(api_request "$GITHUB_API/users/$username")
    
    if echo "$response" | jq -e '.message' > /dev/null 2>&1; then
        local error_message
        error_message=$(echo "$response" | jq -r '.message')
        echo -e "${RED}❌ Error: $error_message${NC}"
        return 1
    fi
    
    local user_type
    user_type=$(echo "$response" | jq -r '.type')
    
    case "$user_type" in
        "User")
            echo -e "${GREEN}✅ Found GitHub user: $username${NC}"
            USER_TYPE="users"
            ;;
        "Organization")
            echo -e "${GREEN}✅ Found GitHub organization: $username${NC}"
            USER_TYPE="orgs"
            ;;
        *)
            echo -e "${RED}❌ Unknown user type: $user_type${NC}"
            return 1
            ;;
    esac
    
    return 0
}

# Get all repositories for user/org
get_repositories() {
    local username="$1"
    local page=1
    local all_repos=()
    
    echo -e "${BLUE}📥 Fetching repository list...${NC}"
    
    while true; do
        local url="$GITHUB_API/$USER_TYPE/$username/repos?per_page=$PER_PAGE&page=$page"
        
        # Add type parameter for specific repo types
        if [ "$INCLUDE_PRIVATE" = "false" ]; then
            url="$url&type=public"
        else
            url="$url&type=all"
        fi
        
        echo -e "${GRAY}   Fetching page $page...${NC}"
        
        local response
        response=$(api_request "$url")
        
        # Check for API errors
        if echo "$response" | jq -e '.message' > /dev/null 2>&1; then
            local error_message
            error_message=$(echo "$response" | jq -r '.message')
            echo -e "${RED}❌ API Error: $error_message${NC}"
            return 1
        fi
        
        # Check if response is an array and has content
        local repos_count
        repos_count=$(echo "$response" | jq '. | length')
        
        if [ "$repos_count" -eq 0 ]; then
            break
        fi
        
        # Process each repository using array indexing instead of base64 encoding
        for ((i=0; i<repos_count; i++)); do
            local repo_json
            repo_json=$(echo "$response" | jq ".[$i]")
            
            local repo_name clone_url is_fork is_private
            repo_name=$(echo "$repo_json" | jq -r '.name')
            is_fork=$(echo "$repo_json" | jq -r '.fork')
            is_private=$(echo "$repo_json" | jq -r '.private')
            
            # Skip forks if not wanted
            if [ "$is_fork" = "true" ] && [ "$INCLUDE_FORKS" = "false" ]; then
                continue
            fi
            
            # Skip private repos if not wanted
            if [ "$is_private" = "true" ] && [ "$INCLUDE_PRIVATE" = "false" ]; then
                continue
            fi
            
            # Get appropriate clone URL
            if [ "$CLONE_METHOD" = "ssh" ]; then
                clone_url=$(echo "$repo_json" | jq -r '.ssh_url')
            else
                clone_url=$(echo "$repo_json" | jq -r '.clone_url')
            fi
            
            all_repos+=("$repo_name|$clone_url|$is_fork|$is_private")
        done
        
        # Check if we got a full page (more pages likely available)
        if [ "$repos_count" -lt "$PER_PAGE" ]; then
            break
        fi
        
        ((page++))
    done
    
    echo -e "${GREEN}✅ Found ${#all_repos[@]} repositories${NC}"
    
    # Store repos in global variable for processing
    REPOSITORIES=("${all_repos[@]}")
    
    return 0
}

# Clone a single repository
clone_repository() {
    local repo_info="$1"
    
    IFS='|' read -r repo_name clone_url is_fork is_private <<< "$repo_info"
    
    local repo_path="$TARGET_DIR/$repo_name"
    local status_prefix="📂 $repo_name"
    
    # Add indicators for fork/private
    if [ "$is_fork" = "true" ]; then
        status_prefix="$status_prefix ${YELLOW}(fork)${NC}"
    fi
    if [ "$is_private" = "true" ]; then
        status_prefix="$status_prefix ${PURPLE}(private)${NC}"
    fi
    
    echo -e "$status_prefix"
    
    if [ "$DRY_RUN" = "true" ]; then
        echo -e "  ${PURPLE}[DRY-RUN] Would clone: $clone_url${NC}"
        return 0
    fi
    
    # Check if repository already exists
    if [ -d "$repo_path" ]; then
        if [ "$UPDATE_EXISTING" = "true" ]; then
            echo -e "  ${BLUE}🔄 Updating existing repository...${NC}"
            cd "$repo_path" || {
                echo -e "  ${RED}❌ Cannot access directory${NC}"
                return 1
            }
            
            if git pull --ff-only &>/dev/null; then
                echo -e "  ${GREEN}✅ Updated successfully${NC}"
            else
                echo -e "  ${YELLOW}⚠️  Update failed - may have local changes${NC}"
            fi
            
            cd - > /dev/null
        else
            echo -e "  ${YELLOW}⏭️  Directory exists, skipping (use --update to update)${NC}"
        fi
        return 0
    fi
    
    # Clone the repository
    echo -e "  ${CYAN}⬇️  Cloning...${NC}"
    
    if git clone "$clone_url" "$repo_path" &>/dev/null; then
        echo -e "  ${GREEN}✅ Cloned successfully${NC}"
        return 0
    else
        echo -e "  ${RED}❌ Clone failed${NC}"
        return 1
    fi
}

# Main execution function
main() {
    local start_time=$(date +%s)
    
    echo -e "${CYAN}=== GitHub Repository Mass Cloner ===${NC}"
    echo -e "${CYAN}Target: $USERNAME${NC}"
    echo -e "${CYAN}Method: $CLONE_METHOD${NC}"
    echo -e "${CYAN}Directory: $TARGET_DIR${NC}"
    echo -e "${CYAN}Parallel jobs: $PARALLEL_JOBS${NC}"
    echo "=============================================="
    
    # Check dependencies
    check_dependencies
    
    # Verify user/org exists
    if ! check_user_exists "$USERNAME"; then
        exit 1
    fi
    
    # Create target directory
    if [ ! -d "$TARGET_DIR" ]; then
        echo -e "${BLUE}📁 Creating target directory: $TARGET_DIR${NC}"
        mkdir -p "$TARGET_DIR" || {
            echo -e "${RED}❌ Cannot create directory: $TARGET_DIR${NC}"
            exit 1
        }
    fi
    
    # Get all repositories
    if ! get_repositories "$USERNAME"; then
        exit 1
    fi
    
    if [ ${#REPOSITORIES[@]} -eq 0 ]; then
        echo -e "${YELLOW}⚠️  No repositories found matching criteria${NC}"
        exit 0
    fi
    
    # Show summary before cloning
    echo ""
    echo -e "${BLUE}📋 Repository Summary:${NC}"
    echo -e "  Total repositories: ${#REPOSITORIES[@]}"
    echo -e "  Clone method: $CLONE_METHOD"
    echo -e "  Include forks: $INCLUDE_FORKS"
    echo -e "  Include private: $INCLUDE_PRIVATE"
    echo -e "  Target directory: $TARGET_DIR"
    echo -e "  Parallel jobs: $PARALLEL_JOBS"
    
    if [ "$DRY_RUN" = "true" ]; then
        echo -e "  ${PURPLE}Mode: DRY RUN (no actual cloning)${NC}"
    fi
    
    echo ""
    
    # Ask for confirmation unless dry run
    if [ "$DRY_RUN" = "false" ]; then
        read -p "Proceed with cloning? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            echo "Cancelled by user"
            exit 0
        fi
    fi
    
    echo -e "${BLUE}🚀 Starting clone process...${NC}"
    echo ""
    
    # Clone repositories (with parallel processing if requested)
    local success_count=0
    local total_count=${#REPOSITORIES[@]}
    
    if [ "$PARALLEL_JOBS" -gt 1 ] && [ "$DRY_RUN" = "false" ]; then
        echo -e "${BLUE}⚡ Using $PARALLEL_JOBS parallel jobs${NC}"
        echo ""
        
        # Export function and variables for parallel execution
        export -f clone_repository
        export TARGET_DIR UPDATE_EXISTING DRY_RUN
        export RED GREEN YELLOW BLUE CYAN PURPLE GRAY NC
        
        # Use parallel processing
        printf '%s\n' "${REPOSITORIES[@]}" | xargs -n 1 -P "$PARALLEL_JOBS" -I {} bash -c 'clone_repository "$@"' _ {}
        
        # Count successful clones
        for repo_info in "${REPOSITORIES[@]}"; do
            IFS='|' read -r repo_name _ _ _ <<< "$repo_info"
            if [ -d "$TARGET_DIR/$repo_name" ]; then
                ((success_count++))
            fi
        done
    else
        # Sequential processing
        for repo_info in "${REPOSITORIES[@]}"; do
            if clone_repository "$repo_info"; then
                ((success_count++))
            fi
        done
    fi
    
    # Show final summary
    local end_time=$(date +%s)
    local duration=$((end_time - start_time))
    
    echo ""
    echo -e "${CYAN}=============================================${NC}"
    echo -e "${GREEN}📊 FINAL SUMMARY:${NC}"
    echo -e "  ${GREEN}Successfully processed: $success_count/$total_count${NC}"
    
    if [ "$DRY_RUN" = "false" ]; then
        echo -e "  ${BLUE}Target directory: $TARGET_DIR${NC}"
    else
        echo -e "  ${PURPLE}Mode: DRY RUN (no actual changes made)${NC}"
    fi
    
    echo -e "  ${GRAY}Duration: ${duration}s${NC}"
    
    if [ "$success_count" -eq "$total_count" ]; then
        echo -e "${GREEN}🎉 All repositories processed successfully!${NC}"
    elif [ "$success_count" -gt 0 ]; then
        echo -e "${YELLOW}⚠️  Some repositories failed. Check the output above.${NC}"
    else
        echo -e "${RED}❌ No repositories were successfully processed.${NC}"
    fi
}

# Parse arguments and run
parse_arguments "$@"
main