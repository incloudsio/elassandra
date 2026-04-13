#!/usr/bin/env bash
# ElasticQueryHandler: OpenSearch Node exposes NamedXContentRegistry via injector(), not getNamedXContentRegistry().
set -euo pipefail
DEST="${1:?OpenSearch clone root}"
F="$DEST/server/src/main/java/org/elassandra/index/ElasticQueryHandler.java"
[[ -f "$F" ]] || exit 0

python3 - "$F" <<'PY'
import pathlib
import re
import sys

path = pathlib.Path(sys.argv[1])
text = path.read_text(encoding="utf-8")
if 'ElassandraDaemon.instance.node().injector().getInstance(NamedXContentRegistry.class)' in text:
    print(f"ElasticQueryHandler NamedXContentRegistry lookup already patched: {path}")
    sys.exit(0)
pattern = re.compile(
    r"""    private static NamedXContentRegistry namedXContentRegistryForQueryParsing\(\) \{
        try \{
            if \(ElassandraDaemon\.instance != null && ElassandraDaemon\.instance\.node\(\) != null\) \{
.*?
            \}
        \} catch \(Throwable ignored\) \{
            // side-car compile stub / Node API without registry
        \}
        return NamedXContentRegistry\.EMPTY;
    \}
""",
    re.S,
)
new = """    private static NamedXContentRegistry namedXContentRegistryForQueryParsing() {
        try {
            if (ElassandraDaemon.instance != null && ElassandraDaemon.instance.node() != null) {
                NamedXContentRegistry registry = ElassandraDaemon.instance.node().injector().getInstance(NamedXContentRegistry.class);
                if (registry != null) {
                    return registry;
                }
            }
        } catch (Throwable ignored) {
            // side-car compile stub / Node API without registry
        }
        return NamedXContentRegistry.EMPTY;
    }
"""
if not pattern.search(text):
    print(f"ElasticQueryHandler registry anchor missing: {path}", file=sys.stderr)
    sys.exit(1)
path.write_text(pattern.sub(new, text, count=1), encoding="utf-8")
print(f"Patched ElasticQueryHandler NamedXContentRegistry lookup: {path}")
PY
