#!/bin/bash

# Log Archive Tool
# Compresses log directories into timestamped .tar.gz archives

set -euo pipefail

# Defaults
DELETE_AFTER=false
CUSTOM_DEST=""
RETENTION_DAYS=7

usage() {
  echo "Usage: $0 <log-directory> [options]"
  echo ""
  echo "Options:"
  echo "  --delete-after    Delete original logs after successful archive"
  echo "  --dest <dir>      Custom destination directory (default: ./archives)"
  echo "  --retention <days> Delete archives older than N days (default: 7)"
  echo "  --no-retention    Skip retention cleanup"
  echo "  -h, --help        Show this help message"
  exit 0
}

# Parse arguments
LOG_DIR=""
while [[ $# -gt 0 ]]; do
  case $1 in
    --delete-after)
      DELETE_AFTER=true
      shift
      ;;
    --dest)
      CUSTOM_DEST="$2"
      shift 2
      ;;
    --retention)
      RETENTION_DAYS="$2"
      shift 2
      ;;
    --no-retention)
      RETENTION_DAYS=0
      shift
      ;;
    -h|--help)
      usage
      ;;
    -*)
      echo "Unknown option: $1" >&2
      exit 1
      ;;
    *)
      if [[ -z "$LOG_DIR" ]]; then
        LOG_DIR="$1"
      else
        echo "Unexpected argument: $1" >&2
        exit 1
      fi
      shift
      ;;
  esac
done

if [[ -z "$LOG_DIR" ]]; then
  echo "Error: No log directory specified." >&2
  echo "Usage: $0 <log-directory> [options]" >&2
  exit 1
fi

if [[ ! -d "$LOG_DIR" ]]; then
  echo "Error: '$LOG_DIR' is not a valid directory." >&2
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
DEST_DIR="${CUSTOM_DEST:-$SCRIPT_DIR/archives}"
LOG_FILE="$SCRIPT_DIR/archive_log.txt"

mkdir -p "$DEST_DIR"

# Size report
DIR_SIZE=$(du -sh "$LOG_DIR" 2>/dev/null | cut -f1)

TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
DIR_BASENAME=$(basename "$LOG_DIR")
ARCHIVE_NAME="logs_archive_${TIMESTAMP}.tar.gz"
ARCHIVE_PATH="$DEST_DIR/$ARCHIVE_NAME"

echo "Archiving '$LOG_DIR' -> '$ARCHIVE_PATH'"

if tar -czf "$ARCHIVE_PATH" -C "$(dirname "$LOG_DIR")" "$DIR_BASENAME"; then
  echo "$(date '+%Y-%m-%d %H:%M:%S') - $ARCHIVE_NAME" >> "$LOG_FILE"
  echo "Archive created successfully: $ARCHIVE_PATH"
else
  echo "Error: Failed to create archive." >&2
  exit 1
fi

# Post-compression size report
ARCHIVE_SIZE=$(du -sh "$ARCHIVE_PATH" 2>/dev/null | cut -f1)
echo ""
echo "--- Size Report ---"
echo "Original directory: $DIR_SIZE"
echo "Compressed archive: $ARCHIVE_SIZE"

# Auto-clean original logs
if $DELETE_AFTER; then
  rm -rf "$LOG_DIR"
  echo ""
  echo "Original logs deleted: $LOG_DIR"
fi

# Retention policy
if [[ "$RETENTION_DAYS" -gt 0 ]]; then
  echo ""
  echo "--- Retention Cleanup (older than $RETENTION_DAYS days) ---"
  DELETED=0
  while IFS= read -r -d '' old_file; do
    echo "Deleting: $old_file"
    rm -f "$old_file"
    DELETED=$((DELETED + 1))
  done < <(find "$DEST_DIR" -name "logs_archive_*.tar.gz" -type f -mtime +"$RETENTION_DAYS" -print0 2>/dev/null)
  if [[ "$DELETED" -eq 0 ]]; then
    echo "No expired archives found."
  fi
fi
