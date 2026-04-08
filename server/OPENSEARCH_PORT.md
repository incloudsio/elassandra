# OpenSearch 1.3.x port (tracking)

This directory tree is still the **Elasticsearch 6.8.4**–based integration from Strapdata. The modernization target is **OpenSearch 1.3.x** (e.g. **1.3.20**) with Elassandra-specific code remaining in `org.elassandra.*`.

## Bootstrap (outside this repo)

From the repository root:

```bash
./scripts/opensearch-port-bootstrap.sh
# Optional: OPENSEARCH_CLONE_DIR=../my-opensearch OPENSEARCH_TAG=1.3.20
```

That clones or reuses a checkout, then creates branch `elassandra-os-1.3` from tag `1.3.20`. Build that tree with **Java 11+** using its own Gradle wrapper.

## Sync `org.elassandra.*` into the side-car

Copies integration sources from this repo into the OpenSearch checkout and rewrites `org.elasticsearch` imports to `org.opensearch` **only under `org/elassandra`** (the clone is modified, not this tree):

```bash
./scripts/sync-elassandra-to-opensearch-sidecar.sh
./scripts/rewrite-elassandra-imports-for-opensearch.sh "${OPENSEARCH_CLONE_DIR:-../opensearch-upstream}"
```

Optional: `OPENSEARCH_SYNC_DRY_RUN=1` on the sync script.

### Cassandra jar + compile probe

`org.elassandra.*` depends on the **Elassandra Cassandra** Ant jar (same as `server/build.gradle` here). Build it when missing:

```bash
./scripts/build-elassandra-cassandra-jar.sh
```

That runs `./gradlew :cassandra-jar` (the Minio S3 test fixture is **skipped by default**; pass `-Delassandra.skipS3TestFixture=false` only if you need it—older Gradle + Docker Compose could fail configuration on **JDK 11**).

Then run the full side-car compile attempt (sync, rewrite imports, attach jar, `:server:compileJava`):

```bash
JAVA_HOME=/path/to/jdk-11 ./scripts/opensearch-sidecar-compile-try.sh
```

The OpenSearch Gradle wrapper often does **not** forward `-Delassandra.cassandra.jar=...` from the CLI to the build JVM. This repo’s script sets **`GRADLE_OPTS`** for you. If you invoke Gradle yourself, use:

```bash
export GRADLE_OPTS="-Delassandra.cassandra.jar=/absolute/path/to/elassandra-cassandra-4.0.20.jar"
./gradlew -I /path/to/elassandra/gradle/opensearch-sidecar-elassandra.init.gradle :server:compileJava
```

`opensearch-sidecar-compile-try.sh` also runs `scripts/patch-opensearch-forbidden-deps-for-elassandra.sh`, which comments out the **Guava** ban in the clone’s `gradle/forbidden-dependencies.gradle` (backup `.bak`). `org.elassandra.*` still uses Guava today. Set `SKIP_OPENSEARCH_FORBIDDEN_DEPS_PATCH=1` to skip that step.

After import rewrite, it runs `scripts/patch-org-elassandra-opensearch-no-schema-update.sh`, which drops `ClusterStateUpdateTask#schemaUpdate()` / `SchemaUpdate` imports that do not exist in OpenSearch 1.3 (Elasticsearch 6.8–only API).

`gradle/opensearch-sidecar-elassandra.init.gradle` adds **commons-lang3** and **slf4j-api** for code paths that compile against the Cassandra jar but not the full OpenSearch dependency graph in isolation.

In this tree, disambiguate **Cassandra** `org.apache.cassandra.schema.IndexMetadata` from cluster **`IndexMetadata`** by using the fully qualified Cassandra type where a secondary index definition is meant (`ElasticSecondaryIndex`, `SchemaManager` secondary-index helpers, `ExtendedElasticSecondaryIndex`). That avoids a name clash after `IndexMetaData` → `IndexMetadata` rewrites.

`scripts/sync-elassandra-fork-minimal-to-opensearch-sidecar.sh` drops in small fork-only types (currently `CqlMapper`) as `org.opensearch.*` until the full mapper rebase lands.

After Cassandra + Guava + minimal stubs, `rewrite-elassandra-imports-for-opensearch.sh` also applies common **7.x renames** (metrics packages flattened, `IndexMetaData` → `IndexMetadata`, `MetaData` → `Metadata`, `ClusterState#metaData()` → `metadata()`, `getTotalHits()` → `getTotalHits().value`).

Remaining errors are mostly **fork-only engine types** not present in stock OpenSearch: `ObjectMapper` / `FieldMapper` implementing `CqlMapper`, `MappedFieldType` / `TypeParsers` CQL hooks, patched `MapperService`, `ClusterService`, discovery transport, etc. Replay those from this repo’s `org.elasticsearch` tree ([Fork touchpoints](#fork-touchpoints-engine-rebase)) into `org.opensearch.*` in the side-car until `org.elassandra.*` compiles.

For the **mapper** layer, export the full forked `index/mapper` sources as a merge reference (does not overwrite OpenSearch):

```bash
./scripts/export-elassandra-mapper-fork-for-opensearch-merge.sh
```

Stage the same fork under `build/` with `package org.opensearch.index.mapper` and engine rewrites applied (for diff/review; still not a drop-in compile):

```bash
./scripts/stage-elassandra-mapper-fork-as-opensearch.sh
./scripts/prioritize-mapper-fork-merge.sh   # CQL-heavy files first
```

See [opensearch_porting_guide.rst](../docs/elassandra/source/developer/opensearch_porting_guide.rst) (Mapper fork section).

## Fork touchpoints (engine rebase)

To list `org/elasticsearch` sources that likely contain Elassandra-specific edits (starting point for manual replay onto `org.opensearch`):

```bash
./scripts/list-elasticsearch-fork-touchpoints.sh
```

## What to port (order)

Follow [docs/elassandra/source/developer/opensearch_porting_guide.rst](../docs/elassandra/source/developer/opensearch_porting_guide.rst): Cassandra daemon bootstrap → discovery/gateway → routing/search → metadata/mappings → shard barriers → `ElasticSecondaryIndex` and REST/query handlers → modules/tests.

## `org.elassandra.*` inventory (approximate)

Java sources live under `server/src/main/java/org/elassandra/` — index, cluster, discovery, gateway, search, shard, cli, env, util. Replace `org.elasticsearch.*` imports with `org.opensearch.*` equivalents when merging into the OpenSearch tree.

## Gradle convergence

When the port compiles in the side-car repo, replace or merge the `server/` implementation here, then update `buildSrc/version.properties` (`opensearch_port`, `lucene_opensearch` are documented target pins) and publishing coordinates. Root `verifyVersions` can use `-Pelassandra.skipLegacyVersionVerify` until Strapdata snapshot metadata is no longer referenced.

Run `./scripts/print-opensearch-port-pins.sh` to print those pins (avoids configuring the full Gradle tree).

## CI

* [.github/workflows/opensearch-sidecar.yml](../.github/workflows/opensearch-sidecar.yml) — weekly / manual upstream `:server:compileJava` on Java 11.
* [.github/workflows/porting-scripts.yml](../.github/workflows/porting-scripts.yml) — `bash -n` on the scripts above.
