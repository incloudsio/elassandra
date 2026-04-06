# Releasing Elassandra

## Documentation builds

- **Read the Docs:** [.readthedocs.yaml](.readthedocs.yaml) at the repo root points Sphinx at [docs/elassandra/source/conf.py](docs/elassandra/source/conf.py) and [docs/elassandra/requirements.txt](docs/elassandra/requirements.txt). Point the RTD project at this file after you change the GitHub remote.
- **CI:** [.github/workflows/docs.yml](.github/workflows/docs.yml) runs `sphinx-build` on every push/PR.
- **Porting:** [.github/workflows/porting-scripts.yml](.github/workflows/porting-scripts.yml) runs [scripts/export-cassandra-elassandra-patches.sh](scripts/export-cassandra-elassandra-patches.sh) so the Cassandra delta export stays working.

## Branching policy

- **`main`** (or **`master`**, depending on the repo default): day-to-day integration for the maintained line; keep it buildable.
- **Release branches**: `release/x.y.z` or `v6.8.4-strapdata`-style names for long-lived maintenance; tag artifacts from these branches.
- **Modernization branch** (optional): `elassandra-os-1.3` or `cassandra-4.0-integration` for work that does not yet compile on the legacy 6.8 tree; merge back when CI is green.

Document the active branch and its Cassandra/OpenSearch baseline in the release notes for every publish.

## Version scheme (current 6.8 line)

Releases use the Elasticsearch-compatible quad **plus** a Cassandra patch segment, for example **6.8.4.16**, defined in [buildSrc/version.properties](buildSrc/version.properties) (`elasticsearch` and `cassandra` coordinates).

- Bump `elasticsearch` / `elasticsearch_vanilla` when changing the search-engine baseline.
- Bump the Cassandra artifact version (`cassandra`) when the `server/cassandra` submodule produces a new `cassandra-all` build.

## Version scheme (future Cassandra 4.0 + OpenSearch 1.3)

When the [OpenSearch 1.3.x](https://github.com/opensearch-project/OpenSearch) rebase ships, publish versions that make the stack obvious to operators, for example:

`4.0.20-1.3.20.1` — Apache Cassandra **4.0.20**, OpenSearch **1.3.20**, Elassandra patch **1**.

Document the mapping in release notes and in [docs/elassandra/source/migration.rst](docs/elassandra/source/migration.rst).

## Build release artifacts

From the repository root (see [CONTRIBUTING.md](CONTRIBUTING.md) for JDK layout on the legacy 6.8 tree):

```bash
./gradlew clean assemble -Dbuild.snapshot=false
```

Outputs are under `distribution/` (tar, zip, packages) per the Gradle projects enabled in this fork.

## Compatibility matrix

For each release, publish a short matrix:

| Elassandra version | Cassandra base | Search engine | Minimum Java | REST compatibility |
|--------------------|----------------|---------------|--------------|---------------------|
| 6.8.4.x (this tree) | Strapdata 3.11.9.x | Elasticsearch 6.8.4 | 8 (C*), 12 (ES) | ES 6.8 |
| Future | Apache 4.0.x + fork | OpenSearch 1.3.x | 11 | OpenSearch 1.x / ES 7.10-style |

## Docker / deb / rpm

Package naming should include the Elassandra version string above. After the OpenSearch port, refresh image tags and registry paths under [https://elassandra.org/](https://elassandra.org/) (canonical site).

## Signing and staging

Use your org’s GPG keys and Maven/Nexus (or GitHub Releases) policy. This repository does not configure external staging servers; add secrets only in CI for your fork.
