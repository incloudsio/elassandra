#!/usr/bin/env bash
# Clone a pinned OpenSearch release for side-by-side porting (outside this repo).
# Usage: OPENSEARCH_TAG=1.3.20 OPENSEARCH_CLONE_DIR=../opensearch-1.3 ./scripts/clone-opensearch-upstream.sh
set -euo pipefail
TAG="${OPENSEARCH_TAG:-1.3.20}"
DEST="${OPENSEARCH_CLONE_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/../opensearch-upstream}"

if [[ -d "$DEST/.git" ]]; then
  echo "Updating existing clone: $DEST"
  git -C "$DEST" remote get-url origin &>/dev/null || \
    git -C "$DEST" remote add origin https://github.com/opensearch-project/OpenSearch.git
  git -C "$DEST" fetch --tags origin
  echo "Ready. Example: cd \"$DEST\" && git checkout -B elassandra-os-1.3 \"$TAG\""
  exit 0
fi

echo "Cloning OpenSearch tag $TAG into $DEST ..."
git clone --depth 1 --branch "$TAG" https://github.com/opensearch-project/OpenSearch.git "$DEST"
echo "Done. Next: create elassandra-os-1.3 branch from $TAG and replay patches (see docs)."
