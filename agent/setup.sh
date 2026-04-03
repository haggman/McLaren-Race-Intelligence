#!/bin/bash
# McLaren Race Intelligence Platform — ADK Agent Setup
# Run this from ~/McLaren-Race-Intelligence/adk-agent/

set -e

echo "=== McLaren Race Intelligence ADK Agent Setup ==="

# Verify environment variables
if [ -z "$PROJECT_ID" ]; then
    echo "ERROR: PROJECT_ID is not set. Run: export PROJECT_ID=\$(gcloud config get-value project)"
    exit 1
fi

if [ -z "$REGION" ]; then
    export REGION="us-central1"
    echo "REGION not set, defaulting to us-central1"
fi

echo "Project : $PROJECT_ID"
echo "Region  : $REGION"

# Create virtual environment and install dependencies
python3 -m venv .venv
source .venv/bin/activate
pip install --upgrade pip
pip install -r requirements.txt

echo ""
echo "=== Setup Complete ==="

