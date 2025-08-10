#!/usr/bin/env bash

# docker-volume-cp - Copy a Docker volume to a new volume with a different name
# Usage: docker-volume-cp <source_volume> <destination_volume>

set -euo pipefail  # Exit on any error, unset variables, or pipe failures

# Function to display usage
usage() {
    echo "Usage: $0 <source_volume> <destination_volume>"
    echo "Example: $0 my_volume my_volume_copy"
    exit 1
}

# Function to cleanup on exit
cleanup() {
    local exit_code=$?

    # Remove temporary containers if they exist
    if [ -n "${SOURCE_CONTAINER:-}" ]; then
        docker rm -f "$SOURCE_CONTAINER" 2>/dev/null || true
    fi
    if [ -n "${DEST_CONTAINER:-}" ]; then
        docker rm -f "$DEST_CONTAINER" 2>/dev/null || true
    fi

    # Remove temporary directory if it exists
    if [ -n "${TEMP_DIR:-}" ] && [ -d "$TEMP_DIR" ]; then
        rm -rf "$TEMP_DIR"
    fi

    if [ $exit_code -ne 0 ]; then
        exit $exit_code
    fi
}

# Set up cleanup trap
trap cleanup EXIT

# Check if correct number of arguments provided
if [ $# -ne 2 ]; then
    usage
fi

SOURCE_VOLUME="$1"
DEST_VOLUME="$2"

# Validate arguments
if [ -z "$SOURCE_VOLUME" ] || [ -z "$DEST_VOLUME" ]; then
    echo "Error: Volume names cannot be empty"
    usage
fi

# Check if source volume exists
if ! docker volume inspect "$SOURCE_VOLUME" >/dev/null 2>&1; then
    echo "Error: Source volume '$SOURCE_VOLUME' does not exist"
    exit 1
fi

# Check if destination volume already exists
if docker volume inspect "$DEST_VOLUME" >/dev/null 2>&1; then
    echo "Error: Destination volume '$DEST_VOLUME' already exists"
    exit 1
fi

# Step 1: Create destination volume
docker volume create "$DEST_VOLUME"

# Step 2: Create temporary containers with volumes mounted
SOURCE_CONTAINER=$(docker create -v "$SOURCE_VOLUME:/data" hello-world)
DEST_CONTAINER=$(docker create -v "$DEST_VOLUME:/data" hello-world)

# Step 3: Create temporary directory and copy data from source volume
TEMP_DIR=$(mktemp -d)
docker cp "$SOURCE_CONTAINER:/data/." "$TEMP_DIR/"

# Step 4: Copy data from temporary directory to destination volume
docker cp "$TEMP_DIR/." "$DEST_CONTAINER:/data/"

# Note: Cleanup will be handled by the EXIT trap
