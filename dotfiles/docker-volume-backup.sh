#!/usr/bin/env bash
set -euo pipefail

# Docker Volume Backup Script using Restic
# Example usage:
# ./docker-volume-backup.sh <volume_name> <restic_repo_path> [backup_name]
# Default backup name is hostname_volume_name

# Check if required arguments are provided
if [ $# -lt 2 ]; then
    echo "Usage: $0 <volume_name> <restic_repo_path> [backup_name]"
    echo "Example: $0 myapp_data /path/to/restic-repo myapp_backup"
    exit 1
fi

VOLUME_NAME="$1"
RESTIC_REPO="$2"
BACKUP_NAME="${3:-$(hostname)_${VOLUME_NAME}}"

# Check if volume exists
if ! docker volume inspect "$VOLUME_NAME" >/dev/null 2>&1; then
    echo "Error: Docker volume '$VOLUME_NAME' does not exist"
    exit 1
fi

# Check if restic repo directory exists
if [ ! -d "$RESTIC_REPO" ]; then
    echo "Error: Restic repository directory '$RESTIC_REPO' does not exist"
    echo "Please create it first or initialize a new restic repository"
    exit 1
fi

# Get absolute path for restic repo
RESTIC_REPO_ABS=$(realpath "$RESTIC_REPO")

echo "Starting backup of volume '$VOLUME_NAME' to repository '$RESTIC_REPO_ABS'"
echo "Backup name: $BACKUP_NAME"

# Run restic backup in a container
docker run -it --rm \
    -v "$VOLUME_NAME":/data:ro \
    -v "$RESTIC_REPO_ABS":/restic \
    -w /data \
    -e RESTIC_REPOSITORY=/restic \
    -e RESTIC_PASSWORD \
    restic/restic:latest \
    backup \
    --host "$BACKUP_NAME" \
    --tag docker,volume,"$BACKUP_NAME" \
    --verbose \
    .

if [ $? -eq 0 ]; then
    echo "Backup completed successfully!"
    echo "Volume: $VOLUME_NAME"
    echo "Repository: $RESTIC_REPO_ABS"
    echo "Host: $BACKUP_NAME"
else
    echo "Backup failed!"
    exit 1
fi
