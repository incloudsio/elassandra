#!/usr/bin/env bash
# One-time (or when updating): push Elassandra Cassandra forks to https://github.com/incloudsio/cassandra
# Requires: git + GitHub auth (gh auth login, or SSH key for git@github.com:incloudsio/cassandra.git).
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
INCLOUDS="${INCLOUDS_REMOTE:-https://github.com/incloudsio/cassandra.git}"

echo "==> 3.11 line (elassandra server/cassandra submodule)"
SUB="$ROOT/server/cassandra"
if [[ ! -d "$SUB/.git" ]]; then
  echo "error: $SUB is not a git checkout (run: git submodule update --init server/cassandra)" >&2
  exit 1
fi
(
  cd "$SUB"
  git remote get-url inclouds &>/dev/null || git remote add inclouds "$INCLOUDS"
  git remote set-url inclouds "$INCLOUDS"
  git checkout -B cassandra-3.11.9-elassandra HEAD
  git push -u inclouds cassandra-3.11.9-elassandra
)

echo "==> 4.0 port (separate clone; set CASSANDRA_40_DIR if not default)"
C40="${CASSANDRA_40_DIR:-$ROOT/../cassandra-4.0-elassandra}"
if [[ -d "$C40/.git" ]]; then
  (
    cd "$C40"
    git remote get-url inclouds &>/dev/null || git remote add inclouds "$INCLOUDS"
    git remote set-url inclouds "$INCLOUDS"
    git push -u inclouds cassandra-4.0.x-elassandra
  )
else
  echo "skip: $C40 not found (clone Apache 4.0 worktree or set CASSANDRA_40_DIR)"
fi

echo "Done. Default branch on GitHub can stay cassandra-3.11.9-elassandra or cassandra-4.0.x-elassandra per team preference."
