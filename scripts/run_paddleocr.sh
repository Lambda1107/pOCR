#!/bin/bash
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
SITE_PACKAGES=$(find "$DIR/venv/lib" -name "site-packages" -type d | head -1)

if [ -z "$SITE_PACKAGES" ]; then
    echo "Error: Python site-packages not found in $DIR/venv" >&2
    exit 1
fi

export PYTHONPATH="$SITE_PACKAGES:$PYTHONPATH"
exec python3 -m paddleocr "$@"
