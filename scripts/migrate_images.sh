#!/bin/bash
# Migrate existing base64 images from DB to image storage backend.
# Usage: ./scripts/migrate_images.sh <API_BASE_URL>
# Example: ./scripts/migrate_images.sh https://ymatch-backend-82867116789.us-west1.run.app

set -e

API_URL="${1:-http://localhost:3000}"
echo "Migrating images on: $API_URL"

# Get all events
EVENTS=$(curl -s "$API_URL/api/v1/events")
EVENT_IDS=$(echo "$EVENTS" | python3 -c "import json,sys; [print(e['id']) for e in json.load(sys.stdin)]")

MIGRATED=0
SKIPPED=0
FAILED=0

for EVENT_ID in $EVENT_IDS; do
  MERCH=$(curl -s "$API_URL/api/v1/events/$EVENT_ID/merch")
  
  echo "$MERCH" | python3 -c "
import json, sys, base64, tempfile, os, subprocess

items = json.load(sys.stdin)
api_url = '$API_URL'
event_id = $EVENT_ID

for item in items:
    photo = item.get('photo_url', '')
    if not photo or not photo.startswith('data:'):
        continue
    
    merch_id = item['id']
    creator_id = item['creator_id']
    name = item['name']
    
    # Parse data URI: data:image/png;base64,AAAA...
    try:
        header, b64data = photo.split(',', 1)
        mime = header.split(':')[1].split(';')[0]
        ext = mime.split('/')[1]
        if ext == 'jpeg': ext = 'jpg'
        
        img_bytes = base64.b64decode(b64data)
        
        # Write to temp file
        tmp = tempfile.NamedTemporaryFile(suffix=f'.{ext}', delete=False)
        tmp.write(img_bytes)
        tmp.close()
        
        # Upload via API
        result = subprocess.run(
            ['curl', '-s', '-X', 'POST', f'{api_url}/api/v1/images/upload', '-F', f'file=@{tmp.name}'],
            capture_output=True, text=True
        )
        os.unlink(tmp.name)
        
        resp = json.loads(result.stdout)
        if 'url' not in resp:
            print(f'  FAIL: merch {merch_id} ({name}): {resp}')
            sys.exit(2)
        
        new_url = resp['url']
        
        # Update merch with new URL
        update = subprocess.run(
            ['curl', '-s', '-X', 'PUT',
             f'{api_url}/api/v1/events/{event_id}/merch/{merch_id}',
             '-H', 'Content-Type: application/json',
             '-d', json.dumps({'user_id': creator_id, 'photo_url': new_url})],
            capture_output=True, text=True
        )
        
        print(f'  OK: merch {merch_id} ({name}) -> {new_url}')
        
    except Exception as e:
        print(f'  FAIL: merch {merch_id} ({name}): {e}')
        sys.exit(2)
"
  
  if [ $? -eq 0 ]; then
    echo "Event $EVENT_ID: done"
  else
    echo "Event $EVENT_ID: FAILED"
    FAILED=$((FAILED + 1))
  fi
done

echo ""
echo "Migration complete."
