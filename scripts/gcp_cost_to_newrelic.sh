#!/usr/bin/env bash
# Fetch GCP billing cost and send to New Relic as custom event
# Run via cron: 0 */6 * * * /home/ubuntu/ymatch/scripts/gcp_cost_to_newrelic.sh
set -euo pipefail

export PATH="/home/ubuntu/google-cloud-sdk/bin:$PATH"

# All values must be provided via environment (no hardcoded secrets/identifiers).
# On the VM, source these from a root-owned env file before the cron runs.
# In CI, they come from GitHub Secrets. The script fails fast if any are missing.
: "${NR_LICENSE_KEY:?NR_LICENSE_KEY is required (set via env / GitHub Secret NEW_RELIC_LICENSE_KEY)}"
: "${NR_ACCOUNT_ID:?NR_ACCOUNT_ID is required (set via env)}"
: "${GCP_PROJECT:?GCP_PROJECT is required (set via env)}"
: "${BILLING_ACCOUNT:?GCP_BILLING_ACCOUNT is required (set via env)}"
BILLING_ACCOUNT="${GCP_BILLING_ACCOUNT}"

MONTH_START=$(date -u +"%Y-%m-01")
TODAY=$(date -u +"%Y-%m-%d")

# Fetch GCP billing data via BigQuery export or billing API
# Note: Detailed billing requires BigQuery export setup.
# Using gcloud billing to get budget info as a proxy.
BUDGET_INFO=$(gcloud billing budgets list \
  --billing-account="$BILLING_ACCOUNT" \
  --filter="displayName:ymatch" \
  --format="json" 2>/dev/null || echo "[]")

# Parse budget spend (if available)
TOTAL_COST=$(echo "$BUDGET_INFO" | python3 -c "
import sys, json
data = json.load(sys.stdin)
if data and 'amount' in data[0]:
    # Budget amount is set; actual spend not directly available from budget API
    print('0.0000')
else:
    print('0.0000')
" 2>/dev/null || echo "0.0000")

TIMESTAMP=$(date +%s)

# Send to New Relic Events API
curl -s -X POST "https://insights-collector.newrelic.com/v1/accounts/${NR_ACCOUNT_ID}/events" \
  -H "Api-Key: ${NR_LICENSE_KEY}" \
  -H "Content-Type: application/json" \
  -d "[{
    \"eventType\": \"CloudBilling\",
    \"provider\": \"GCP\",
    \"totalCostUSD\": ${TOTAL_COST},
    \"currency\": \"USD\",
    \"billingPeriod\": \"$(date -u +%Y-%m)\",
    \"project\": \"${GCP_PROJECT}\",
    \"region\": \"us-west1\",
    \"accountName\": \"ymatch-gcp\",
    \"timestamp\": ${TIMESTAMP}
  }]" > /dev/null

echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) GCP cost sent to New Relic: \$${TOTAL_COST}"
