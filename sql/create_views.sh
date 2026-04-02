#!/bin/bash
# Creates all McLaren Race Intelligence views in BigQuery.
#
# Reads views.sql, splits it into individual CREATE OR REPLACE VIEW
# statements, and executes each one separately with clear feedback.
#
# The SQL source is views.sql in this directory — open it in
# Cloud Shell Editor to examine the view definitions before running.
#
# Usage: bash sql/create_views.sh

set -e

PROJECT_ID=${PROJECT_ID:?"PROJECT_ID environment variable is not set. Run: export PROJECT_ID=\$(gcloud config get-value project)"}
SQL_DIR="$(cd "$(dirname "$0")" && pwd)"
SQL_FILE="${SQL_DIR}/views.sql"

echo "Creating McLaren Race Intelligence views in project ${PROJECT_ID}..."
echo ""

# Strip comment-only lines and blank lines, then process line by line.
# Each CREATE OR REPLACE VIEW ... ; block is collected and executed individually.
CLEAN_SQL=$(sed '/^[[:space:]]*--/d; /^[[:space:]]*$/d' "${SQL_FILE}")

VIEW_COUNT=0
CURRENT=""

while IFS= read -r line; do
  CURRENT="${CURRENT}${line}"$'\n'

  # A semicolon at the end of a line marks the end of a complete statement
  if [[ "${line}" =~ \;[[:space:]]*$ ]]; then
    if [[ "${CURRENT}" == *"CREATE OR REPLACE VIEW"* ]]; then
      # Extract the view name for display
      VIEW_NAME=$(echo "${CURRENT}" | grep -o '`f1_data\.[^`]*`' | head -1 | tr -d '`')
      VIEW_COUNT=$((VIEW_COUNT + 1))

      echo "  [${VIEW_COUNT}/6] Creating ${VIEW_NAME}..."
      bq query --use_legacy_sql=false --project_id="${PROJECT_ID}" "${CURRENT}" > /dev/null 2>&1
      echo "         ✓ Done"
    fi
    CURRENT=""
  fi
done <<< "${CLEAN_SQL}"

echo ""
echo "All ${VIEW_COUNT} views created successfully."
