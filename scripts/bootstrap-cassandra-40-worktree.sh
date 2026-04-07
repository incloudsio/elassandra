#!/usr/bin/env bash
# Clone Apache Cassandra and create a branch for Elassandra 4.0.x porting (sibling directory).
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TAG="${CASSANDRA_APACHE_TAG:-cassandra-4.0.20}"
BRANCH="${CASSANDRA_40_BRANCH:-cassandra-4.0.x-elassandra}"
DEST="${CASSANDRA_40_CLONE_DIR:-$ROOT/../cassandra-4.0-elassandra}"
APACHE_URL="${APACHE_URL:-https://github.com/apache/cassandra.git}"

if [[ -d "$DEST/.git" ]]; then
  echo "Already a git repo: $DEST"
  echo "  cd \"$DEST\" && git fetch --tags origin && git checkout \"$TAG\" && git checkout -b \"$BRANCH\""
  exit 0
fi

echo "Cloning Apache Cassandra into $DEST ..."
git clone "$APACHE_URL" "$DEST"
cd "$DEST"
git fetch --tags origin
git checkout "$TAG"
git checkout -b "$BRANCH"

echo ""
echo "Created branch $BRANCH at $TAG in $DEST"
echo "Suggested remotes (pick one):"
echo "  git remote add inclouds https://github.com/incloudsio/cassandra.git"
echo "  git fetch inclouds cassandra-4.0.x-elassandra"
echo "  # or, for comparison with the legacy Strapdata fork:"
echo "  git remote add strapdata https://github.com/strapdata/cassandra.git && git fetch strapdata"
echo "Apply Elassandra delta (expect conflicts):"
echo "  (from elassandra repo) ./scripts/export-cassandra-elassandra-patches.sh"
echo "  cd \"$DEST\" && git am --3way $ROOT/build/cassandra-elassandra-patches/*.patch"
