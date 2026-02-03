#!/bin/bash

# Syncer - Git repository synchronization tool
# This script synchronizes multiple git repositories with their remote counterparts

CONFIG_FILE="$HOME/.config/syncer/config.yaml"
LOG_FILE="$HOME/.config/syncer/syncer.log"
LOG_MAX_SIZE=5242880 # 5MB in bytes
LOG_KEEP_COUNT=5
STATE_DIR="$HOME/.config/syncer/state"

# Create state directory if it doesn't exist
mkdir -p "$STATE_DIR"

# Function to log messages with timestamp
log_message() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >>"$LOG_FILE"
}

# Function to rotate log files
rotate_logs() {
    if [ -f "$LOG_FILE" ]; then
        local log_size=$(stat -f%z "$LOG_FILE" 2>/dev/null || stat -c%s "$LOG_FILE" 2>/dev/null)
        if [ "$log_size" -gt "$LOG_MAX_SIZE" ]; then
            log_message "Rotating log files..."

            # Remove oldest log if we have too many
            if [ -f "${LOG_FILE}.${LOG_KEEP_COUNT}" ]; then
                rm -f "${LOG_FILE}.${LOG_KEEP_COUNT}"
            fi

            # Rotate existing logs
            for i in $(seq $((LOG_KEEP_COUNT - 1)) -1 1); do
                if [ -f "${LOG_FILE}.$i" ]; then
                    mv "${LOG_FILE}.$i" "${LOG_FILE}.$((i + 1))"
                fi
            done

            # Move current log to .1
            mv "$LOG_FILE" "${LOG_FILE}.1"
            touch "$LOG_FILE"
        fi
    fi
}

# Function to parse YAML (simple implementation for our specific format)
parse_yaml() {
    local yaml_file="$1"
    local prefix="$2"

    # Extract default-cron
    DEFAULT_CRON=$(grep "^default-cron:" "$yaml_file" | sed "s/default-cron:[[:space:]]*'\(.*\)'/\1/" | tr -d "'\"")

    # Extract repositories
    local in_repos=false
    local repo_index=0

    while IFS= read -r line; do
        # Check if we're in the repositories section
        if [[ "$line" =~ ^repositories: ]]; then
            in_repos=true
            continue
        fi

        if $in_repos; then
            # Parse path
            if [[ "$line" =~ ^[[:space:]]*-[[:space:]]*path:[[:space:]]*(.*) ]]; then
                local path="${BASH_REMATCH[1]}"
                path=$(echo "$path" | tr -d "'\"")
                REPO_PATHS[$repo_index]="$path"
                # Set default cron for this repo
                REPO_CRONS[$repo_index]="$DEFAULT_CRON"
            # Parse cron (optional override)
            elif [[ "$line" =~ ^[[:space:]]+cron:[[:space:]]*(.*) ]]; then
                local cron="${BASH_REMATCH[1]}"
                cron=$(echo "$cron" | tr -d "'\"")
                REPO_CRONS[$repo_index]="$cron"
                ((repo_index++))
            fi
        fi
    done <"$yaml_file"
}

# Function to check if it's time to sync based on cron schedule
should_sync() {
    local repo_path="$1"
    local cron_schedule="$2"
    local state_file="$STATE_DIR/$(echo "$repo_path" | md5sum | cut -d' ' -f1).state"

    # If no cron schedule, skip
    if [ -z "$cron_schedule" ]; then
        return 1
    fi

    # Parse cron schedule: minute hour day month weekday
    IFS=' ' read -r minute hour day month weekday <<<"$cron_schedule"

    local current_minute=$(date +%M | sed 's/^0*//')
    local current_hour=$(date +%H | sed 's/^0*//')
    local current_day=$(date +%d | sed 's/^0*//')
    local current_month=$(date +%m | sed 's/^0*//')
    local current_weekday=$(date +%w)

    # Simple cron matching (supports *, specific values, and ranges)
    match_cron_field() {
        local field="$1"
        local current="$2"

        # Handle * (always match)
        if [ "$field" = "*" ]; then
            return 0
        fi

        # Handle step values (e.g., */5, 0/2)
        if [[ "$field" =~ ^([0-9]+)?/([0-9]+)$ ]]; then
            local start="${BASH_REMATCH[1]:-0}"
            local step="${BASH_REMATCH[2]}"
            if [ $((current % step)) -eq $((start % step)) ]; then
                return 0
            fi
            return 1
        fi

        # Handle exact match
        if [ "$field" = "$current" ]; then
            return 0
        fi

        return 1
    }

    # Check if current time matches cron schedule
    if match_cron_field "$minute" "$current_minute" &&
        match_cron_field "$hour" "$current_hour" &&
        match_cron_field "$day" "$current_day" &&
        match_cron_field "$month" "$current_month" &&
        match_cron_field "$weekday" "$current_weekday"; then

        # Check if we've already synced in this minute
        local current_timestamp=$(date +%Y%m%d%H%M)
        if [ -f "$state_file" ]; then
            local last_sync=$(cat "$state_file")
            if [ "$last_sync" = "$current_timestamp" ]; then
                return 1 # Already synced in this minute
            fi
        fi

        # Update state file
        echo "$current_timestamp" >"$state_file"
        return 0
    fi

    return 1
}

# Function to synchronize a git repository
sync_repository() {
    local repo_path="$1"

    log_message "Starting sync for repository: $repo_path"

    # Check if directory exists
    if [ ! -d "$repo_path" ]; then
        log_message "ERROR: Repository path does not exist: $repo_path"
        return 1
    fi

    # Check if it's a git repository
    if [ ! -d "$repo_path/.git" ]; then
        log_message "ERROR: Not a git repository: $repo_path"
        return 1
    fi

    cd "$repo_path" || {
        log_message "ERROR: Cannot change to directory: $repo_path"
        return 1
    }

    # Check for local changes
    if [ -n "$(git status --porcelain)" ]; then
        log_message "Local changes detected in $repo_path, committing..."
        git add -A >>"$LOG_FILE" 2>&1
        git commit -m "Auto-sync commit" >>"$LOG_FILE" 2>&1
        if [ $? -eq 0 ]; then
            log_message "Successfully committed local changes in $repo_path"
        else
            log_message "ERROR: Failed to commit local changes in $repo_path"
        fi
    else
        log_message "No local changes in $repo_path"
    fi

    # Get current branch
    local current_branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null)
    if [ -z "$current_branch" ]; then
        log_message "ERROR: Cannot determine current branch in $repo_path"
        return 1
    fi

    # Fetch latest changes
    log_message "Fetching latest changes from remote for $repo_path..."
    git fetch origin >>"$LOG_FILE" 2>&1
    if [ $? -ne 0 ]; then
        log_message "ERROR: Failed to fetch from remote in $repo_path"
        return 1
    fi

    # Pull with strategy to favor remote on conflicts
    log_message "Pulling latest changes for $repo_path..."
    git pull origin "$current_branch" --strategy=recursive --strategy-option=theirs >>"$LOG_FILE" 2>&1
    if [ $? -eq 0 ]; then
        log_message "Successfully pulled changes in $repo_path"
    else
        log_message "ERROR: Failed to pull changes in $repo_path"
    fi

    # Push local commits
    log_message "Pushing local commits for $repo_path..."
    git push origin "$current_branch" >>"$LOG_FILE" 2>&1
    if [ $? -eq 0 ]; then
        log_message "Successfully pushed changes in $repo_path"
    else
        log_message "WARNING: Failed to push changes in $repo_path (may be up to date or no upstream)"
    fi

    log_message "Completed sync for repository: $repo_path"
    return 0
}

# Main execution
main() {
    # Rotate logs if needed
    rotate_logs

    log_message "=== Syncer started ==="

    # Check if config file exists
    if [ ! -f "$CONFIG_FILE" ]; then
        log_message "ERROR: Configuration file not found: $CONFIG_FILE"
        log_message "Please create a configuration file at $CONFIG_FILE"
        exit 1
    fi

    # Parse configuration
    declare -a REPO_PATHS
    declare -a REPO_CRONS
    DEFAULT_CRON=""

    parse_yaml "$CONFIG_FILE"

    # Sync each repository if it's time
    for i in "${!REPO_PATHS[@]}"; do
        local repo_path="${REPO_PATHS[$i]}"
        local cron_schedule="${REPO_CRONS[$i]}"

        if should_sync "$repo_path" "$cron_schedule"; then
            sync_repository "$repo_path"
        fi
    done

    log_message "=== Syncer completed ==="
}

# Run main function
main
