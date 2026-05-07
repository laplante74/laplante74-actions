#!/usr/bin/env bash
# sn-change.sh
# Called by the servicenow-devops-change composite action.
# All values come in as environment variables — see action.yml.

set -euo pipefail

# ── Helper: print masked log line ─────────────────────────────────────────
log() { echo "[sn-change] $*"; }

# ── Helper: POST / PATCH with consistent headers ──────────────────────────
sn_curl() {
  local method="$1"
  local url="$2"
  local body="$3"

  curl \
    --silent \
    --show-error \
    --fail-with-body \
    --max-time 30 \
    --retry 3 \
    --retry-delay 5 \
    --retry-all-errors \
    -X "$method" \
    -H "Content-Type: application/json" \
    -H "devops-integration-token: ${SN_TOKEN}" \
    -H "tool-id: ${SN_TOOL_ID}" \
    "$url" \
    -d "$body"
}

# ── CLOSE PATH ────────────────────────────────────────────────────────────
if [[ "${AUTO_CLOSE}" == "true" ]]; then
  log "Closing change request: ${SYS_ID_IN}"

  if [[ "${DEPLOY_STATUS}" == "success" ]]; then
    CLOSE_STATE="closed_successful"
    CLOSE_CODE="successful"
  else
    CLOSE_STATE="closed_incomplete"
    CLOSE_CODE="unsuccessful"
  fi
  BODY=$(jq -n \
    --arg state        "${CLOSE_STATE}" \
    --arg close_code   "${CLOSE_CODE}" \
    --arg actual_start "${ACTUAL_START}" \
    --arg actual_end   "${ACTUAL_END}" \
    --arg work_notes   "${WORK_NOTES}" \
    '{
      state:             $state,
      close_code:        $close_code,
      actual_start_date: $actual_start,
      actual_end_date:   $actual_end,
      work_notes:        $work_notes
    }')
  RESPONSE=$(sn_curl PATCH \
    "${SN_URL}/api/sn_devops/devops/change/${SYS_ID_IN}" \
    "$BODY")
  log "Close response: ${RESPONSE}"
  # Emit outputs
  {
    echo "change_request_number="
    echo "change_request_sys_id=${SYS_ID_IN}"
    echo "change_request_url=${SN_URL}/nav_to.do?uri=change_request.do?sys_id=${SYS_ID_IN}"
  } >> "$GITHUB_OUTPUT"
  log "Change ${SYS_ID_IN} closed (${CLOSE_STATE})."
  exit 0
fi
# ── CREATE PATH ───────────────────────────────────────────────────────────
log "Creating change request..."
BODY=$(jq -n \
  --arg short_description  "${SHORT_DESC}" \
  --arg description        "${DESCRIPTION}" \
  --arg implementation_plan "${IMPL_PLAN}" \
  --arg backout_plan       "${BACKOUT_PLAN}" \
  --arg test_plan          "${TEST_PLAN}" \
  --arg assignment_group   "${ASSIGN_GROUP}" \
  --arg assigned_to        "${ASSIGNED_TO}" \
  --arg work_notes         "${WORK_NOTES}" \
  '{
    autoCloseChange: false,
    attributes: {
      short_description:   $short_description,
      description:         $description,
      implementation_plan: $implementation_plan,
      backout_plan:        $backout_plan,
      test_plan:           $test_plan,
      assignment_group:    $assignment_group,
      assigned_to:         $assigned_to,
      work_notes:          $work_notes
    }
  }')
RESPONSE=$(sn_curl POST \
  "${SN_URL}/api/sn_devops/devops/change" \
  "$BODY")
log "Create response: ${RESPONSE}"
# Parse the response — fail loudly if the sys_id is missing
SYS_ID=$(echo "${RESPONSE}" | jq -r '.result.sys_id // empty')
NUMBER=$(echo  "${RESPONSE}" | jq -r '.result.number  // empty')
if [[ -z "${SYS_ID}" ]]; then
  echo "::error::ServiceNow did not return a sys_id. Full response:"
  echo "${RESPONSE}"
  exit 1
fi
log "Created change: ${NUMBER} (${SYS_ID})"
{
  echo "change_request_number=${NUMBER}"
  echo "change_request_sys_id=${SYS_ID}"
  echo "change_request_url=${SN_URL}/nav_to.do?uri=change_request.do?sys_id=${SYS_ID}"
} >> "$GITHUB_OUTPUT"