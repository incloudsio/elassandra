#!/usr/bin/env bash
# Export git format-patch series for Strapdata Elassandra commits on top of Apache 3.11.9.
# Run from repo root. Requires server/cassandra submodule initialized.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SUB="$ROOT/server/cassandra"
OUT="${PATCH_OUT:-$ROOT/build/cassandra-elassandra-patches}"
APACHE_REMOTE="${APACHE_REMOTE:-apache}"
APACHE_URL="${APACHE_URL:-https://github.com/apache/cassandra.git}"
BASE_TAG="${CASSANDRA_BASE_TAG:-cassandra-3.11.9}"

if [[ ! -f "$SUB/build.xml" ]]; then
  echo "error: $SUB missing — run: git submodule update --init server/cassandra" >&2
  exit 1
fi

mkdir -p "$OUT"
cd "$SUB"

if ! git remote get-url "$APACHE_REMOTE" &>/dev/null; then
  echo "Adding git remote $APACHE_REMOTE -> $APACHE_URL"
  git remote add "$APACHE_REMOTE" "$APACHE_URL"
fi

echo "Fetching tag $BASE_TAG from $APACHE_REMOTE ..."
git fetch "$APACHE_REMOTE" "refs/tags/$BASE_TAG:refs/tags/$BASE_TAG" 2>/dev/null || \
  git fetch "$APACHE_REMOTE" --tags --depth=1

if ! git rev-parse "$BASE_TAG^{commit}" &>/dev/null; then
  echo "error: tag $BASE_TAG not available after fetch" >&2
  exit 1
fi

BASE="$(git merge-base HEAD "$BASE_TAG")"
echo "Merge-base with $BASE_TAG: $BASE"
echo "HEAD: $(git rev-parse HEAD)"
COUNT="$(git rev-list --count "$BASE"..HEAD)"
echo "Commits to export: $COUNT"

rm -f "$OUT"/*.patch
git format-patch "$BASE"..HEAD -o "$OUT"

echo ""
echo "Wrote $COUNT patches to $OUT"
echo "Next (on your Cassandra 4.0 branch): git am --3way $OUT/*.patch"
echo "Expect conflicts; many hunks must be rewritten for Cassandra 4.0 APIs."
