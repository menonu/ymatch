#!/usr/bin/env bash
# Setup New Relic Infrastructure Agent on Ubuntu 24.04 ARM64
# Usage: NEW_RELIC_LICENSE_KEY=xxx ./scripts/setup_newrelic_agent.sh
#
# This is the imperative equivalent of the cloud-init in terraform/oci/main.tf.
# Prefer terraform for new instances; use this script for existing VMs.
set -euo pipefail

if [ -z "${NEW_RELIC_LICENSE_KEY:-}" ]; then
  echo "ERROR: NEW_RELIC_LICENSE_KEY environment variable is required"
  exit 1
fi

echo "=== Installing New Relic Infrastructure Agent ==="

# 1. License key config
cat > /tmp/newrelic-infra.yml <<EOF
license_key: ${NEW_RELIC_LICENSE_KEY}
display_name: ymatch-oci-arm
EOF
sudo mv /tmp/newrelic-infra.yml /etc/newrelic-infra.yml

# 2. GPG key
curl -fsSL https://download.newrelic.com/infrastructure_agent/gpg/newrelic-infra.gpg \
  | sudo gpg --dearmor -o /etc/apt/trusted.gpg.d/newrelic-infra.gpg --yes

# 3. Apt repo (noble = Ubuntu 24.04, arm64)
echo "deb [arch=arm64] https://download.newrelic.com/infrastructure_agent/linux/apt noble main" \
  | sudo tee /etc/apt/sources.list.d/newrelic-infra.list > /dev/null

# 4. Install
sudo apt-get update -qq
sudo apt-get install -y -qq newrelic-infra

# 5. Enable Docker integration
sudo mkdir -p /etc/newrelic-infra/integrations.d
cat <<'DOCKER_CONF' | sudo tee /etc/newrelic-infra/integrations.d/docker-config.yml > /dev/null
integrations:
  - name: nri-docker
    interval: 30s
DOCKER_CONF

# 6. Log forwarding config (backend + caddy + db logs)
sudo mkdir -p /etc/newrelic-infra/logging.d
BACKEND_ID=$(docker inspect --format='{{.Id}}' ymatch_backend 2>/dev/null || echo "")
CADDY_ID=$(docker inspect --format='{{.Id}}' ymatch_caddy 2>/dev/null || echo "")
DB_ID=$(docker inspect --format='{{.Id}}' ymatch_db 2>/dev/null || echo "")

if [ -n "$BACKEND_ID" ]; then
  cat <<LOGCONF | sudo tee /etc/newrelic-infra/logging.d/docker-logs.yml > /dev/null
logs:
  - name: ymatch-backend
    file: /var/lib/docker/containers/${BACKEND_ID}/${BACKEND_ID}-json.log
    attributes:
      logtype: ymatch-backend
      service: backend
      environment: oci-production
  - name: ymatch-caddy
    file: /var/lib/docker/containers/${CADDY_ID}/${CADDY_ID}-json.log
    attributes:
      logtype: ymatch-caddy
      service: caddy
      environment: oci-production
  - name: ymatch-db
    file: /var/lib/docker/containers/${DB_ID}/${DB_ID}-json.log
    attributes:
      logtype: ymatch-db
      service: postgresql
      environment: oci-production
LOGCONF
fi

# 7. OCI billing Flex integration (requires OCI CLI + instance principal)
if command -v oci &>/dev/null; then
  TENANCY_OCID="${OCI_TENANCY_OCID:-}"
  REGION="${OCI_REGION:-ap-osaka-1}"
  if [ -n "$TENANCY_OCID" ]; then
    cat <<FLEXCONF | sudo tee /etc/newrelic-infra/integrations.d/oci-billing-config.yml > /dev/null
integrations:
  - name: nri-flex
    interval: 6h
    config:
      name: OCIBillingFlex
      apis:
        - event_type: OCIBillingSample
          commands:
            - run: /usr/local/bin/oci_billing_to_nr.sh
              split_by: ":"
FLEXCONF

    cat > /tmp/oci_billing_to_nr.sh <<BILLING
#!/bin/bash
MONTH_START=\$(date -u +"%Y-%m-01T00:00:00.000Z")
TOMORROW=\$(date -u -d "+1 day" +"%Y-%m-%dT00:00:00.000Z")

RESULT=\$(oci usage-api usage-summary request-summarized-usages \\
  --auth instance_principal \\
  --tenant-id "$TENANCY_OCID" \\
  --time-usage-started "\$MONTH_START" \\
  --time-usage-ended "\$TOMORROW" \\
  --granularity MONTHLY \\
  --query-type COST 2>/dev/null)

COST=\$(echo "\$RESULT" | python3 -c "
import sys, json
data = json.load(sys.stdin)
items = data.get('data', {}).get('items', [])
print(sum(float(i.get('computed-amount', 0) or 0) for i in items))
" 2>/dev/null || echo "0")

echo "totalCostUSD:\$COST"
echo "provider:OCI"
echo "billingPeriod:\$(date -u +%Y-%m)"
echo "region:$REGION"
BILLING
    sudo mv /tmp/oci_billing_to_nr.sh /usr/local/bin/oci_billing_to_nr.sh
    sudo chmod +x /usr/local/bin/oci_billing_to_nr.sh
  fi
fi

# 8. Restart agent
sudo systemctl restart newrelic-infra
sudo systemctl enable newrelic-infra

echo "=== New Relic Infrastructure Agent installed ==="
sudo systemctl status newrelic-infra --no-pager -l | head -20
