#!/usr/bin/env bash
# Mark every *.sh in the repository executable so you do not need `chmod +x` on each new script.
# Safe to run anytime (idempotent). Excludes files under .git/.
#
# Usage (from repo root):
#   ./scripts/setup-script-permissions.sh
#   bash scripts/setup-script-permissions.sh   # first time if not +x yet
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
count=0
while IFS= read -r -d '' f; do
  chmod +x "$f" || exit 1
  count=$((count + 1))
done < <(find "$ROOT" -type f -name '*.sh' ! -path '*/.git/*' -print0)
echo "chmod +x on ${count} *.sh under ${ROOT}"
