#!/usr/bin/env bash
set -euo pipefail

# Docker Volume Restore Script using Restic
# Usage example:
# ./docker-volume-restore.sh <volume_name> <restic_repo_path> [backup_name]
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

# Check if restic repo directory exists
if [ ! -d "$RESTIC_REPO" ]; then
    echo "Error: Restic repository directory '$RESTIC_REPO' does not exist"
    exit 1
fi

# Get absolute path for restic repo
RESTIC_REPO_ABS=$(realpath "$RESTIC_REPO")

# Check if volume exists, create if it doesn't
if ! docker volume inspect "$VOLUME_NAME" >/dev/null 2>&1; then
    echo "Volume '$VOLUME_NAME' does not exist. Creating it..."
    docker volume create "$VOLUME_NAME"
    echo "Volume '$VOLUME_NAME' created successfully"
else
    echo "Warning: Volume '$VOLUME_NAME' already exists. Its contents will be overwritten."
    read -p "Do you want to continue? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Restore cancelled"
        exit 0
    fi
fi

echo "Starting restore of volume '$VOLUME_NAME' from repository '$RESTIC_REPO_ABS'"
echo "Backup name: $BACKUP_NAME"

# Check if snapshots exist for the specified host
echo "Checking for available snapshots for host '$BACKUP_NAME'..."
SNAPSHOT_COUNT=$(docker run -it --rm \
    -v "$RESTIC_REPO_ABS":/restic \
    -e RESTIC_REPOSITORY=/restic \
    -e RESTIC_PASSWORD \
    restic/restic:latest \
    snapshots \
    --host "$BACKUP_NAME" \
    --tag docker,volume,"$VOLUME_NAME" \
    --json | jq length 2>/dev/null || echo "0")

if [ "$SNAPSHOT_COUNT" = "0" ]; then
    echo "Error: No snapshots found for host '$BACKUP_NAME' with volume '$VOLUME_NAME'"
    exit 1
fi

echo "Found $SNAPSHOT_COUNT snapshot(s). Using latest snapshot..."

# Clear the volume first by mounting it and removing all contents
echo "Clearing existing volume contents..."
docker run --rm \
    -v "$VOLUME_NAME":/data \
    alpine:latest \
    sh -c "rm -rf /data/* /data/.[!.]* /data/..?* 2>/dev/null || true"

# Restore from restic backup (always use latest)
echo "Restoring from latest backup..."
docker run -it --rm \
    -v "$VOLUME_NAME":/data \
    -v "$RESTIC_REPO_ABS":/restic \
    -w /data \
    -e RESTIC_REPOSITORY=/restic \
    -e RESTIC_PASSWORD \
    restic/restic:latest \
    restore latest \
    --host "$BACKUP_NAME" \
    --tag docker,volume,"$BACKUP_NAME" \
    --target /data \
    --verbose

if [ $? -eq 0 ]; then
    echo "Restore completed successfully!"
    echo "Volume: $VOLUME_NAME"
    echo "Repository: $RESTIC_REPO_ABS"
    echo "Host: $BACKUP_NAME"

    # Show volume info
    echo ""
    echo "Volume information:"
    docker volume inspect "$VOLUME_NAME"
else
    echo "Restore failed!"
    exit 1
fi
