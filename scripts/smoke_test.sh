#!/bin/bash

# Configuration
API_URL="http://localhost:3000/api/v1"
TEST_UUID="smoke-test-uuid-$(date +%s)"

echo "Starting YMatch API Smoke Tests..."
echo "API URL: $API_URL"

# Helper function to check response code
check_status() {
    local status=$1
    local expected=$2
    local step=$3
    if [ "$status" -ne "$expected" ]; then
        echo "❌ FAILED: $step (Expected $expected, got $status)"
        exit 1
    else
        echo "✅ PASSED: $step"
    fi
}

# 1. Test Guest Login
echo -e "\n1. Testing Guest Login..."
LOGIN_RESP=$(curl -s -w "\n%{http_code}" -X POST "$API_URL/auth/guest" -H "Content-Type: application/json" -d "{\"uuid\": \"$TEST_UUID\"}")
LOGIN_STATUS=$(echo "$LOGIN_RESP" | tail -n1)
LOGIN_BODY=$(echo "$LOGIN_RESP" | sed '$d')
check_status "$LOGIN_STATUS" 200 "Guest Login"

USER_ID=$(echo "$LOGIN_BODY" | grep -o '"id":[0-9]*' | cut -d':' -f2)
echo "   User ID: $USER_ID"

# 2. Test Create Event
echo -e "\n2. Testing Create Event..."
EVENT_RESP=$(curl -s -w "\n%{http_code}" -X POST "$API_URL/events" -H "Content-Type: application/json" -d "{\"name\": \"Smoke Test Event\", \"creator_id\": $USER_ID}")
EVENT_STATUS=$(echo "$EVENT_RESP" | tail -n1)
EVENT_BODY=$(echo "$EVENT_RESP" | sed '$d')
check_status "$EVENT_STATUS" 200 "Create Event"

EVENT_ID=$(echo "$EVENT_BODY" | grep -o '"id":[0-9]*' | cut -d':' -f2)
echo "   Event ID: $EVENT_ID"

# 3. Test List Events
echo -e "\n3. Testing List Events..."
LIST_RESP=$(curl -s -w "\n%{http_code}" -X GET "$API_URL/events")
LIST_STATUS=$(echo "$LIST_RESP" | tail -n1)
check_status "$LIST_STATUS" 200 "List Events"

echo -e "\n🎉 All smoke tests passed successfully!"
exit 0
