# Syncer - Git Repository Synchronization Tool

## Overview

Syncer is a shell script that automatically synchronizes multiple git repositories with their remote counterparts based on customizable cron schedules.

## Installation

The syncer script is located at: `~/Programs/syncer/syncer.sh`

Configuration and logs are stored in: `~/.config/syncer/`

## Configuration

Edit the configuration file at `~/.config/syncer/config.yaml`:

```yaml
default-cron: '0 2 * * *'
repositories:
  - path: /path/to/repo1
    cron: '0/2 * * * *'
  - path: /path/to/repo2
    cron: '0 2 * * *'
```

### Cron Schedule Format

The cron schedule follows the standard format: `minute hour day month weekday`

Examples:

- `0 2 * * *` - Run at 2:00 AM every day
- `*/5 * * * *` - Run every 5 minutes
- `0/2 * * * *` - Run every 2 minutes starting from minute 0
- `30 14 * * *` - Run at 2:30 PM every day

## Setup Cron Job

To run syncer every minute via cron:

1. Open crontab editor:

   ```bash
   crontab -e
   ```

2. Add this line:

   ```
   * * * * * ~/Programs/syncer/syncer.sh
   ```

3. Save and exit.

## Features

- **Automatic Commits**: Commits local changes with "Auto-sync commit" message
- **Pull & Push**: Pulls latest changes and pushes local commits
- **Conflict Resolution**: Resolves merge conflicts by favoring remote changes
- **Scheduled Execution**: Each repository can have its own cron schedule
- **Logging**: All actions are logged to `~/.config/syncer/syncer.log`
- **Log Rotation**: Automatically rotates logs when they exceed 5MB (keeps last 5 logs)
- **Error Handling**: Gracefully handles errors and logs issues

## Logs

Logs are stored at: `~/.config/syncer/syncer.log`

Old logs are rotated to: `syncer.log.1`, `syncer.log.2`, etc.

## How It Works

1. Syncer runs every minute via cron
2. It checks each repository's cron schedule to determine if it should sync
3. For repositories that are due for sync:
   - Commits any local changes
   - Pulls latest changes from remote
   - Pushes local commits to remote
   - Resolves conflicts favoring remote changes
4. All actions are logged with timestamps

## Notes

- The script tracks the last sync time for each repository to prevent multiple syncs within the same minute
- The script is compatible with bash on macOS and Linux
- Log files are automatically excluded from git commits (add to .gitignore if needed)
