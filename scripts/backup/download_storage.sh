#!/usr/bin/env bash
# Downloads every stored file (all buckets) into $1/<bucket>/<path>, for the
# nightly backup (.github/workflows/db-backup.yml). The file list comes from
# storage.objects through the database; each file is fetched with the
# service role key, so private buckets are included. Prints counts only.
set -euo pipefail

dest="${1:?usage: download_storage.sh <dest dir>}"
: "${SUPABASE_DB_URL:?}" "${SUPABASE_URL:?}" "${SUPABASE_SERVICE_ROLE_KEY:?}"
mkdir -p "$dest"

list=$(mktemp)
psql "$SUPABASE_DB_URL" -X -v ON_ERROR_STOP=1 -At -F $'\t' -c \
  "select bucket_id, name from storage.objects
    where name is not null and right(name, 1) <> '/'
    order by bucket_id, name" > "$list"

total=$(wc -l < "$list")
ok=0
failed=0
while IFS=$'\t' read -r bucket name; do
  [ -n "$bucket" ] || continue
  out="$dest/$bucket/$name"
  mkdir -p "$(dirname "$out")"
  # Each path segment URL-encoded; slashes kept.
  enc=$(python3 -c 'import sys, urllib.parse; print(urllib.parse.quote(sys.argv[1], safe="/"))' "$name")
  if curl -sS -f --retry 3 --max-time 120 \
       -H "Authorization: Bearer $SUPABASE_SERVICE_ROLE_KEY" \
       -H "apikey: $SUPABASE_SERVICE_ROLE_KEY" \
       -o "$out" "$SUPABASE_URL/storage/v1/object/authenticated/$bucket/$enc"; then
    ok=$((ok + 1))
  else
    failed=$((failed + 1))
    echo "could not download a file in bucket $bucket"
  fi
done < "$list"
rm -f "$list"

echo "stored files: $total listed, $ok downloaded, $failed failed"
if [ "$failed" -gt 0 ]; then
  echo "::error::$failed stored file(s) could not be downloaded"
  exit 1
fi
