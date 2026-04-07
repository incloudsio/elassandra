# OpenSearch 1.3.x port (tracking)

This directory tree is still the **Elasticsearch 6.8.4**–based integration from Strapdata. The modernization target is **OpenSearch 1.3.x** (e.g. **1.3.20**) with Elassandra-specific code remaining in `org.elassandra.*`.

## Bootstrap (outside this repo)

From the repository root:

```bash
./scripts/opensearch-port-bootstrap.sh
# Optional: OPENSEARCH_CLONE_DIR=../my-opensearch OPENSEARCH_TAG=1.3.20
```

That clones or reuses a checkout, then creates branch `elassandra-os-1.3` from tag `1.3.20`. Build that tree with **Java 11+** using its own Gradle wrapper.

## What to port (order)

Follow [docs/elassandra/source/developer/opensearch_porting_guide.rst](../docs/elassandra/source/developer/opensearch_porting_guide.rst): Cassandra daemon bootstrap → discovery/gateway → routing/search → metadata/mappings → shard barriers → `ElasticSecondaryIndex` and REST/query handlers → modules/tests.

## `org.elassandra.*` inventory (approximate)

Java sources live under `server/src/main/java/org/elassandra/` — index, cluster, discovery, gateway, search, shard, cli, env, util. Replace `org.elasticsearch.*` imports with `org.opensearch.*` equivalents when merging into the OpenSearch tree.

## Gradle convergence

When the port compiles in the side-car repo, replace or merge the `server/` implementation here, then update `buildSrc/version.properties` (`opensearch_port`, `lucene_opensearch` are documented target pins) and publishing coordinates. Root `verifyVersions` can use `-Pelassandra.skipLegacyVersionVerify` until Strapdata snapshot metadata is no longer referenced.
