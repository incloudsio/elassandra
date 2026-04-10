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

Prepare also installs Elassandra’s **`ESSingleNodeTestCase`** fork as **`OpenSearchSingleNodeTestCase`** (`sync-elassandra-essingle-node-testcase-to-opensearch-sidecar.sh`) and applies bootstrap/test patches—required for **`compileTestJava`**.

Then run the full side-car compile attempt (sync, rewrite imports, attach jar, then **`:server:compileJava`**, **`:test:framework:compileJava`**, and **`:server:compileTestJava`** by default):

```bash
JAVA_HOME=/path/to/jdk-11 ./scripts/opensearch-sidecar-compile-try.sh
```

To compile only main sources (faster): `OPENSEARCH_SIDECAR_TASKS=:server:compileJava ./scripts/opensearch-sidecar-compile-try.sh`

### Side-car `:server:test` (integration; often not green yet)

`org.elassandra.*` tests extend **`ESSingleNodeTestCase`** / **`OpenSearchSingleNodeTestCase`** and expect a **real Elassandra node** (Cassandra + search engine), not the compile-time stubs in the side-car overlay. Running them is still useful to see which runtime pieces are missing after `compileTestJava` succeeds.

```bash
JAVA_HOME=/path/to/jdk-11 ./scripts/opensearch-sidecar-test-try.sh
```

The script runs `opensearch-sidecar-prepare.sh`, then `./gradlew :server:test` with a **Gradle `--tests` filter**. By default it runs a single class (`org.elassandra.ClusterSettingsTests`) as a smoke run. To target more tests:

```bash
OPENSEARCH_SIDECAR_TEST_PATTERN='org.elassandra.PendingClusterStateTests' ./scripts/opensearch-sidecar-test-try.sh
# Full package (slow; needs full runtime wiring):
# OPENSEARCH_SIDECAR_TEST_PATTERN='org.elassandra.*' ./scripts/opensearch-sidecar-test-try.sh
```

Expect failures until **`ElassandraDaemon`** (and related bootstrap: `cassandra.home`, discovery, gateway) is fully ported and tests can start a real embedded cluster. Compile-only CI success does **not** imply `:server:test` passes.

`opensearch-sidecar-test-try.sh` sets **`RUNTIME_JAVA_HOME`** to **`JAVA_HOME`** when unset so OpenSearch does not try to download a separate “bundled” JDK for tests (which can fail on **Apple Silicon** or air‑gapped hosts). Override **`RUNTIME_JAVA_HOME`** if you need a different JVM for test execution than for Gradle.

By default the script sets **`cassandra.home`** and **`cassandra.config`** (as a `file:` URI) using the first layout that exists: **`ELASSANDRA_TEST_CASSANDRA_HOME`** (if set), else **`server/src/test/resources`** (minimal yaml aligned with embedded **`org.elassandra.*`** tests and the Elassandra Cassandra jar), else **`distribution/src`**. It also creates default **`data/`**, **`commitlog/`**, **`saved_caches/`**, and **`hints/`** under that root when present so embedded tests can write without missing-directory errors.

**`gradle/opensearch-sidecar-elassandra.init.gradle`** forwards matching **`System` properties** from the Gradle JVM to forked **`Test`** workers for keys starting with **`cassandra.`**, **`jna.`**, **`io.netty.`**, and **`org.apache.cassandra.`** (so you can pass extra `-D` flags via **`GRADLE_OPTS`**). It adds **`-Djna.nosys=true`** to test JVMs so **JNA** prefers natives bundled with **`jna.jar`** (reduces **`UnsatisfiedLinkError`** on hosts without a system **`libjna`**). **`opensearch.set.netty.runtime.available.processors`** is a **boolean** (`true` / `false`) read by **`Netty4Utils`**, not a CPU count—**`OPENSEARCH_NETTY_PROCESSORS`** defaults to **`false`** in **`opensearch-sidecar-test-try.sh`** (skip pinning); set to **`true`** if you want Netty to call **`setAvailableProcessors`** from the runtime value. The init script mirrors whatever value is on the Gradle JVM into forked test JVMs. For extra heap or logging flags, use **`ELASSANDRA_OPENSEARCH_TEST_EXTRA_JVM_ARGS`** (space-separated, forwarded by the init script).

**`SKIP_ELASSANDRA_TEST_CASSANDRA_SYS_PROPS=1`** skips automatic **`cassandra.home`** / **`cassandra.config`** defaults.

The Elassandra Cassandra jar expects **SnakeYAML 1.x** for `YamlConfigurationLoader`; OpenSearch pins **2.x**, so the init script **forces SnakeYAML 1.26** on server classpaths. Even then, the checked-in **`conf/cassandra.yaml`** must match the **Cassandra 4.0** `Config` schema expected by the forked jar—if tests fail YAML construction errors, point **`ELASSANDRA_TEST_CASSANDRA_HOME`** at a full Elassandra/Cassandra tree with a valid 4.0 config (for example under **`server/cassandra`**) instead of the minimal test fixture.

**Test waves (curated `--tests` sets):** set **`OPENSEARCH_SIDECAR_TEST_WAVE`** to **`0`**–**`4`** to run predefined slices (see script header in **`scripts/opensearch-sidecar-test-try.sh`**): wave **0** = smoke (**`ClusterSettingsTests`** only); **1** adds metadata/settings; **2** adds CQL/index; **3** adds cluster/discovery/snapshots; **4** = full **`org.elassandra.*`**. You can still pass an explicit comma-separated **`OPENSEARCH_SIDECAR_TEST_PATTERN`** when **`OPENSEARCH_SIDECAR_TEST_WAVE`** is unset.

**Logging:** if tests fail with **`PrefixLogger`** or log4j initialization assertions, try **`ELASSANDRA_OPENSEARCH_TEST_EXTRA_JVM_ARGS='-Dlog4j2.disable.jmx=true'`** or align OpenSearch test **`log4j2`** configuration with the side-car **`Test`** worker (upstream **`server/src/test/resources`** in the clone).

**Embedded `Config` (recommended for side-car tests):** **`scripts/patch-opensearch-essingle-node-config-override.sh`** (run from **`opensearch-sidecar-prepare.sh`**) patches **`test/framework/.../ESSingleNodeTestCase`** to call **`DatabaseDescriptor.daemonInitialization(() -> { ... })`** with a **`Config`** built from **`cassandra.home`** (paths, **`CommitLogSync.periodic`**, partitioner, snitch, seeds) instead of **`cassandra.yaml`**, avoiding **`YamlConfigurationLoader`** / SnakeYAML edge cases. Set **`-Delassandra.test.config.override=false`** to use YAML again. The merged **`ElassandraDaemon`** template uses **`LogManager.getLogger`** (not **`Loggers.getLogger(Class)`**) so OpenSearch 1.3 **`PrefixLogger`** does not throw on empty prefixes.

**`ESSingleNodeTestCase` embedded OpenSearch bootstrap (prepare patches):** **`patch-opensearch-essingle-node-activate-createnode.sh`** wires **`ElassandraDaemon.activate(..., createNode=true)`**, **`ringReady()` → `super.ringReady()`**, **`getPlugins()` → `getMockPlugins()`**, always loads **`MockNioTransportPlugin`**, merges **`http.type`** to **`netty4`** after env settings (empty **`http.type`** from prepared config otherwise breaks **`NetworkModule`**), and registers **`Netty4Plugin`** via reflection so **`ElassandraNode`** gets HTTP/transport factories (**`patch-opensearch-server-test-runtime-netty4.sh`** adds **`testRuntimeOnly project(':modules:transport-netty4')`** to the clone’s **`server/build.gradle`**—the embedded node only loads explicit classpath plugins). **`path.data`** must not live under Lucene’s mock **`PathUtils`** tree (see **`patch-opensearch-essingle-node-mock-fs-data-path.sh`** for legacy **`initElassandraDeamon(..., opensearchDataPath)`** wiring): **`setUp()`** calls **`super.setUp()`**, saves the Lucene mock **`FileSystem`**, **`PathUtilsForTesting.teardown()`**, creates a **real** temp directory under **`java.io.tmpdir`**, runs **`initElassandraDeamon`**, then **`PathUtilsForTesting.installMock(saved)`** so the rest of the test still sees the Lucene mock filesystem. Mixing mock **`PathUtils`** with **`cassandra.home/data/elasticsearch.data`** can yield **`FileAlreadyExistsException`** / **`NoSuchFileException`** on **`nodes/0`**, suite **SKIPPED**, or Gradle worker **exit 100**.

**Debugging opaque `exit value 100`:** run with **`--stacktrace`**, **`-Dtests.output=true`**, ensure **`scripts/opensearch-sidecar-test-try.sh`** (it runs **`:server:cleanTest`** and removes **`server/build/testrun`** in the clone). Pass **`-Dtests.security.manager=false`** (the script does). If the JUnit XML shows **`AccessControlException`** during **`DatabaseDescriptor`** static init, the security manager is still on. If logs show mock-FS failures under **`cassandra.home`**, confirm the mock-fs data path patch is applied.

**Lucene mock FS / `java.io.tmpdir` / `FileAlreadyExistsException`:** the forked test JVM and Lucene’s test harness can disagree on temp directories (see the header comment in **`gradle/opensearch-sidecar-elassandra.init.gradle`**). Side-car patches (**`patch-opensearch-test-base-delete-testrun-before-mkdir.sh`**, **`patch-opensearch-test-base-no-precreate-temp.sh`**) reduce stale **`testrun/`** / **`temp`** issues. For Gradle/Lucene worker races, run a **single** forked test JVM: **`OPENSEARCH_SIDECAR_TESTS_JVMS=1 ./scripts/opensearch-sidecar-test-try.sh`** (forwards **`-Dtests.jvms=1`**). GitHub Actions side-car test workflows set this by default.

**Cassandra runtime jars on the OpenSearch classpath:** **`gradle/opensearch-sidecar-elassandra.init.gradle`** adds the Elassandra Cassandra jar plus transitive needs surfaced by **`daemonInitialization` / `CassandraDaemon.setup`** (e.g. **high-scale-lib**, **jamm**, **lz4-java**, **caffeine**, **jctools**, Netty modules, **`--add-opens java.base/jdk.internal.ref=ALL-UNNAMED`**). **Guava** is **19** at compile (legacy Elassandra) and **forced to the OpenSearch pin** (e.g. **32.x**) on **runtime** / **testRuntime** classpaths so Cassandra’s **`HostAndPort.getHost()`** resolves at runtime.

### ElassandraDaemon and real bootstrap (next runtime milestone)

By default **`sync-elassandra-fork-overlay-to-opensearch-sidecar.sh`** installs **`scripts/templates/ElassandraDaemon-opensearch-merged.java`**: a port of the production **`ElassandraDaemon`** from this repo to **`org.opensearch.*`** ( **`CassandraDaemon`** lifecycle, **`OpenSearchBootstrap`** reflection for package-private bootstrap, **`Node(Environment, …)`**, **`injector().getInstance(ClusterService.class)`**, etc.). Set **`ELASSANDRA_SIDE_CAR_ELASSANDRA_DAEMON=stub`** to use the smaller **`ElassandraDaemon-opensearch-sidecar-stub.java`** instead (compile-only / minimal runtime).

**`scripts/patch-opensearch-node-elassandra-activate.sh`** adds **`Node#activate()`** (delegates to **`start()`**) so **`activateAndWaitShards`** matches the Elasticsearch 6.8 fork API.

Full **`:server:test`** for **`org.elassandra.*`** still depends on a healthy local Cassandra config, JNA, and logging init (see test output for **`PrefixLogger`** / **`JNA`** on some hosts). Treat **`opensearch-sidecar-test-try.sh`** as a **diagnostic** runner until those environments are stable.

The **main** Elassandra tree still ships the Elasticsearch 6.8 **`ElassandraDaemon`** under [`ElassandraDaemon.java`](src/main/java/org/apache/cassandra/service/ElassandraDaemon.java); converge that file with the merged template when you cut over **`server/`** to OpenSearch. Track work in the porting guide’s recommended order (daemon → discovery/gateway → routing → metadata).

The OpenSearch Gradle wrapper often does **not** forward `-Delassandra.cassandra.jar=...` from the CLI to the build JVM. This repo’s script sets **`GRADLE_OPTS`** for you. If you invoke Gradle yourself, use:

```bash
export GRADLE_OPTS="-Delassandra.cassandra.jar=/absolute/path/to/elassandra-cassandra-4.0.20.jar"
./gradlew -I /path/to/elassandra/gradle/opensearch-sidecar-elassandra.init.gradle :server:compileJava
```

`opensearch-sidecar-compile-try.sh` also runs `scripts/patch-opensearch-forbidden-deps-for-elassandra.sh`, which comments out the **Guava** ban in the clone’s `gradle/forbidden-dependencies.gradle` (backup `.bak`). `org.elassandra.*` still uses Guava today. Set `SKIP_OPENSEARCH_FORBIDDEN_DEPS_PATCH=1` to skip that step.

After import rewrite, it runs `scripts/patch-org-elassandra-opensearch-no-schema-update.sh`, which drops `ClusterStateUpdateTask#schemaUpdate()` / `SchemaUpdate` imports that do not exist in OpenSearch 1.3 (Elasticsearch 6.8–only API).

`gradle/opensearch-sidecar-elassandra.init.gradle` adds **commons-lang3** and **slf4j-api** for code paths that compile against the Cassandra jar but not the full OpenSearch dependency graph in isolation. **httpclient** / **httpcore** versions are read from the clone’s `buildSrc/version.properties` so they stay aligned with the rest of the Gradle build (avoids resolution conflicts when running `:server:compileTestJava`).

To rewrite **`server/src/test/java/org/elassandra`** imports after the **test framework** is ported (`ESSingleNodeTestCase` → `OpenSearchSingleNodeTestCase` with CQL helpers, `MockCassandraDiscovery`, etc.), use:

```bash
./scripts/rewrite-elassandra-opensearch-tests.sh "${OPENSEARCH_CLONE_DIR:-../incloudsio-opensearch}"
```

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

A checked-in snapshot of that list (regenerate after large fork edits) lives at [`elasticsearch-fork-touchpoints.list`](elasticsearch-fork-touchpoints.list) in this directory.

## What to port (order)

Follow [docs/elassandra/source/developer/opensearch_porting_guide.rst](../docs/elassandra/source/developer/opensearch_porting_guide.rst): Cassandra daemon bootstrap → discovery/gateway → routing/search → metadata/mappings → shard barriers → `ElasticSecondaryIndex` and REST/query handlers → modules/tests.

## `org.elassandra.*` inventory (approximate)

Java sources live under `server/src/main/java/org/elassandra/` — index, cluster, discovery, gateway, search, shard, cli, env, util. Replace `org.elasticsearch.*` imports with `org.opensearch.*` equivalents when merging into the OpenSearch tree.

## Gradle convergence

When the port compiles in the side-car repo, replace or merge the `server/` implementation here, then update `buildSrc/version.properties` (`opensearch_port`, `lucene_opensearch` are documented target pins) and publishing coordinates. Root `verifyVersions` can use `-Pelassandra.skipLegacyVersionVerify` until Strapdata snapshot metadata is no longer referenced.

Run `./scripts/print-opensearch-port-pins.sh` to print those pins (avoids configuring the full Gradle tree).

## CI

* **Linux Docker (local debug):** `ci/docker/opensearch-sidecar-debug/` — JDK 11 image with `git` and `rsync`. Run `./ci/docker/opensearch-sidecar-debug/run.sh` (mounts this repo and `OPENSEARCH_CLONE_DIR`, default `../incloudsio-opensearch`) to reproduce side-car compile/tests away from macOS native issues.
* [.github/workflows/opensearch-sidecar.yml](../.github/workflows/opensearch-sidecar.yml) — weekly / manual upstream `:server:compileJava` on Java 11.
* [.github/workflows/elassandra-opensearch-sidecar-compile.yml](../.github/workflows/elassandra-opensearch-sidecar-compile.yml) — Elassandra sync + patches + side-car `compileJava` / `compileTestJava` on PRs and `main`/`master`.
* [.github/workflows/elassandra-opensearch-sidecar-test.yml](../.github/workflows/elassandra-opensearch-sidecar-test.yml) — **manual** (`workflow_dispatch`): runs `opensearch-sidecar-test-try.sh` on **`ubuntu-latest`**. Choose **wave** `0`–`4` in the workflow UI (default **`0`** = smoke); same as **`OPENSEARCH_SIDECAR_TEST_WAVE`** locally.
* [.github/workflows/elassandra-opensearch-sidecar-test-full.yml](../.github/workflows/elassandra-opensearch-sidecar-test-full.yml) — **weekly** (Mondays 06:00 UTC) and **manual**: full **`org.elassandra.*`** slice (**wave 4**). Uses **`continue-on-error: true`** until the full package is green.
* [.github/workflows/porting-scripts.yml](../.github/workflows/porting-scripts.yml) — `bash -n` on the scripts above.
