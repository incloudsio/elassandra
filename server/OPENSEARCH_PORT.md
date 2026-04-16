# OpenSearch 1.3.x port status

This repository's main `server/` tree is now the OpenSearch **1.3.20**-based Elassandra integration.
The side-car flow remains useful, but it is now a maintenance and future-rebase harness rather than the
primary source tree.

## Current baseline

- Main build target: OpenSearch **1.3.20** with Lucene **8.10.1**.
- Cassandra base: Apache **4.0.20** via `server/cassandra`.
- Embedded test status: side-car regression waves `0` through `4` are green and the full wave-4 CI job is expected to pass without `continue-on-error`.

## When to use the side-car

Use the side-car scripts when rebasing to a newer OpenSearch tag or when replaying Elassandra-specific
fork deltas onto a fresh upstream checkout:

```bash
./scripts/opensearch-port-bootstrap.sh
./scripts/opensearch-sidecar-prepare.sh
JAVA_HOME=/path/to/jdk-11 ./scripts/opensearch-sidecar-test-try.sh
```

That flow remains the safest place to validate upstream API drift before importing the result back into
the main repository.

## Main-tree expectations

- `server/src/main/java/org/opensearch/**` is the shipped engine tree.
- `server/src/main/java/org/elassandra/**` remains the Elassandra bridge layer.
- `server/src/main/java/org/apache/cassandra/service/ElassandraDaemon.java` is the OpenSearch-aware bootstrap entrypoint used by the merged tree.
- `buildSrc/version.properties` carries the OpenSearch and Cassandra release pins used by the build and release docs.

## Future rebases

For future OpenSearch upgrades, keep using the side-car scripts and the touchpoint inventory approach from
`docs/elassandra/source/developer/opensearch_porting_guide.rst` so the Elassandra-specific delta stays explicit
instead of drifting into ad-hoc patch scripts.
