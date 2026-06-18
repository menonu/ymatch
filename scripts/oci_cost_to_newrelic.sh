#!/usr/bin/env bash
# Fetch OCI billing cost and send to New Relic as custom event
# Run via cron: 0 */6 * * * /home/ubuntu/ymatch/scripts/oci_cost_to_newrelic.sh
set -euo pipefail

export SUPPRESS_LABEL_WARNING=True

# All values must be provided via environment (no hardcoded secrets/identifiers).
# On the VM, source these from a root-owned env file before the cron runs.
# In CI, they come from GitHub Secrets. The script fails fast if any are missing.
: "${NR_LICENSE_KEY:?NR_LICENSE_KEY is required (set via env / GitHub Secret NEW_RELIC_LICENSE_KEY)}"
: "${NR_ACCOUNT_ID:?NR_ACCOUNT_ID is required (set via env)}"
: "${OCI_TENANCY:?OCI_TENANCY is required (set via env)}"

MONTH_START=$(date -u +"%Y-%m-01T00:00:00.000Z")
TOMORROW=$(date -u -d "+1 day" +"%Y-%m-%dT00:00:00.000Z")

# Fetch OCI cost data
COST_JSON=$(oci usage-api usage-summary request-summarized-usages \
  --tenant-id "$OCI_TENANCY" \
  --time-usage-started "$MONTH_START" \
  --time-usage-ended "$TOMORROW" \
  --granularity MONTHLY \
  --query-type COST \
  2>/dev/null || echo '{"data":{"items":[]}}')

# Parse total cost (sum of all items, or 0)
TOTAL_COST=$(echo "$COST_JSON" | python3 -c "
import sys, json
data = json.load(sys.stdin)
items = data.get('data', {}).get('items', [])
total = sum(float(i.get('computed-amount', 0) or 0) for i in items)
print(f'{total:.4f}')
" 2>/dev/null || echo "0.0000")

# Also get per-service breakdown
SERVICE_COSTS=$(echo "$COST_JSON" | python3 -c "
import sys, json
data = json.load(sys.stdin)
items = data.get('data', {}).get('items', [])
services = {}
for i in items:
    svc = i.get('service', 'unknown')
    amt = float(i.get('computed-amount', 0) or 0)
    services[svc] = services.get(svc, 0) + amt
if not services:
    print('none')
else:
    print('; '.join(f'{k}=\${v:.4f}' for k, v in services.items()))
" 2>/dev/null || echo "none")

TIMESTAMP=$(date +%s)

# Send to New Relic Events API
curl -s -X POST "https://insights-collector.newrelic.com/v1/accounts/${NR_ACCOUNT_ID}/events" \
  -H "Api-Key: ${NR_LICENSE_KEY}" \
  -H "Content-Type: application/json" \
  -d "[{
    \"eventType\": \"CloudBilling\",
    \"provider\": \"OCI\",
    \"totalCostUSD\": ${TOTAL_COST},
    \"currency\": \"USD\",
    \"billingPeriod\": \"$(date -u +%Y-%m)\",
    \"serviceBreakdown\": \"${SERVICE_COSTS}\",
    \"region\": \"ap-osaka-1\",
    \"accountName\": \"ymatch-oci\",
    \"timestamp\": ${TIMESTAMP}
  }]" > /dev/null

echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) OCI cost sent to New Relic: \$${TOTAL_COST} (${SERVICE_COSTS})"
