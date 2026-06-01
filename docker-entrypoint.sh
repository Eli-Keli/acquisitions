#!/bin/sh
# Container entrypoint — runs before the main CMD (e.g. npm start)

set -e          # Exit immediately if any command fails
exec "$@"       # Replace shell with the main process (passes signals correctly)
