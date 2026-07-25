#!/usr/bin/env bash
# One-shot DuckDNS A-record update (issue #523).
#
# Usage (env vars):
#   DUCKDNS_DOMAIN   subdomain only, e.g. ymatch (not ymatch.duckdns.org)
#   DUCKDNS_TOKEN    account token
#   DUCKDNS_IP       IPv4 address to publish
#
# Prints domains + IP + API response; never prints the token.
# Exit 0 only when DuckDNS returns OK.
set -euo pipefail

: "${DUCKDNS_DOMAIN:?DUCKDNS_DOMAIN is required (subdomain only, e.g. ymatch)}"
: "${DUCKDNS_TOKEN:?DUCKDNS_TOKEN is required}"
: "${DUCKDNS_IP:?DUCKDNS_IP is required}"

# Basic shape checks — avoid accidental full FQDN or empty fields.
if [[ "$DUCKDNS_DOMAIN" == *.* ]]; then
  echo "ERROR: DUCKDNS_DOMAIN must be the bare subdomain (got: $DUCKDNS_DOMAIN)" >&2
  exit 1
fi

if [[ ! "$DUCKDNS_IP" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "ERROR: DUCKDNS_IP must be an IPv4 address (got: $DUCKDNS_IP)" >&2
  exit 1
fi

resp="$(curl -fsS --get \
  --data-urlencode "domains=${DUCKDNS_DOMAIN}" \
  --data-urlencode "token=${DUCKDNS_TOKEN}" \
  --data-urlencode "ip=${DUCKDNS_IP}" \
  "https://www.duckdns.org/update")"

echo "duckdns update domains=${DUCKDNS_DOMAIN} ip=${DUCKDNS_IP}: ${resp}"

if [ "$resp" != "OK" ]; then
  echo "ERROR: DuckDNS update failed (expected OK)" >&2
  exit 1
fi
