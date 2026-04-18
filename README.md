# Elassandra [![Build](https://github.com/incloudsio/elassandra/actions/workflows/build.yml/badge.svg)](https://github.com/incloudsio/elassandra/actions/workflows/build.yml) [![Documentation Status](https://readthedocs.org/projects/elassandra-ng/badge/?version=latest)](https://elassandra-ng.readthedocs.io/en/latest/?badge=latest) [![GitHub release](https://img.shields.io/github/v/release/incloudsio/elassandra.svg)](https://github.com/incloudsio/elassandra/releases/latest)

![Elassandra Logo](elassandra-logo.png)

**Site:** [https://elassandra.org/](https://elassandra.org/)

This repository is a **fork** of [Strapdata Elassandra](https://github.com/strapdata/elassandra). The maintained community home is **[github.com/incloudsio/elassandra](https://github.com/incloudsio/elassandra)** under **Elassandra.org**, with **inClouds** and **Maxim Tsarenko (maxts)** among the active maintainers. Original Strapdata history and copyright remain with Strapdata and other contributors; see [License](#license) and [NOTICE.txt](NOTICE.txt).

## Current Line: Cassandra 4.0.x + OpenSearch 1.3.x

The **`modernization/cassandra4-opensearch13`** branch now carries an **OpenSearch 1.3.20**-based `server/` tree on **Apache Cassandra 4.0.x** via the [incloudsio/cassandra](https://github.com/incloudsio/cassandra) fork checked out under `server/cassandra` (branch **`cassandra-4.0.x-elassandra`**). That line includes the JVM port of the Elassandra bridge to Cassandra 4.0 APIs (`InetAddressAndPort`, `org.apache.cassandra.schema.*`, CQL `QueryHandler`, secondary index lifecycle, packaging, and test fixes) plus the merged OpenSearch bootstrap, cluster, mapper, and test-framework updates needed for the embedded search runtime.

**CI** builds with **GitHub Actions** (`.github/workflows/build.yml`), **Java 11** (`JAVA11_HOME`) for Gradle and the Cassandra Ant build, and **Python 3** for installing `cqlsh` libraries into `.deb` / `.rpm` packages. For older pre-OpenSearch release lines and their branch-specific guidance, refer to the historical [strapdata/elassandra](https://github.com/strapdata/elassandra) repository.

Developer references: [RELEASING.md](RELEASING.md) and `docs/elassandra/source/` (`migration.rst`, `developer/cassandra_fork_inventory.rst`, `developer/cassandra_40_rebase.rst`, `developer/cassandra_40_jvm_port.rst`, `developer/opensearch_porting_guide.rst`). **Scripts:** `scripts/export-cassandra-elassandra-patches.sh`, `scripts/bootstrap-cassandra-40-worktree.sh`, `scripts/check-cassandra-submodule.sh`, `scripts/use-cassandra-40-submodule.sh`, `scripts/clone-opensearch-upstream.sh`, `scripts/opensearch-port-bootstrap.sh`, `scripts/opensearch-sidecar-prepare.sh`, `scripts/opensearch-sidecar-compile-try.sh`, `scripts/opensearch-sidecar-test-try.sh` (optional `:server:test` probe; see `server/OPENSEARCH_PORT.md`).

### OpenSearch 1.3 Port Status

The main repository now carries the OpenSearch-based tree, while the side-car scripts remain the rebase and regression harness for future upstream OpenSearch updates. The curated side-car regression waves `0` through `4` are green on this branch, and the full wave-4 workflow is expected to pass without `continue-on-error`.

## What Elassandra is (today)

Elassandra is an [Apache Cassandra](https://cassandra.apache.org/) distribution that embeds an [OpenSearch](https://github.com/opensearch-project/OpenSearch) 1.3 search engine in each node.
Elassandra is a multi-master database and search layer with support for replicating across multiple datacenters in active/active mode.

OpenSearch code runs inside Cassandra JVMs to index and query Cassandra data; Cassandra stores indexed documents and cluster metadata.

![Elassandra architecture](/docs/elassandra/source/images/elassandra1.jpg)

Elassandra supports Cassandra vnodes and scales horizontally by adding more nodes without the need to reshard indices.

Documentation: **[elassandra.org](https://elassandra.org/en/latest/)** (project site) and **[Read the Docs — elassandra-ng](https://elassandra-ng.readthedocs.io/en/latest/?badge=latest)** (hosted Sphinx build). You can also build from [docs/elassandra](docs/elassandra) locally.

## Benefits of Elassandra

For Cassandra users, elassandra provides OpenSearch features:
* Cassandra updates are indexed in OpenSearch.
* Full-text and spatial search on your Cassandra data.
* Real-time aggregation (does not require Spark or Hadoop to GROUP BY)
* Provide search on multiple keyspaces and tables in one query.
* Provide automatic schema creation and support nested documents using [User Defined Types](https://docs.datastax.com/en/cql/3.1/cql/cql_using/cqlUseUDT.html).
* Provide read/write JSON REST access to Cassandra data.
* Support OpenSearch plugins.
* Manage concurrent OpenSearch mapping changes and apply batched atomic CQL schema changes.
* Support [OpenSearch ingest processors](https://docs.opensearch.org/latest/ingest-pipelines/processors/index-processors/) to transform input data.

For OpenSearch users, elassandra provides useful features:
* Elassandra is masterless. Cluster state is managed through [cassandra lightweight transactions](http://www.datastax.com/dev/blog/lightweight-transactions-in-cassandra-2-0).
* Elassandra is a sharded multi-master database, while OpenSearch coordinates sharded search workloads on top of Cassandra replication. Thus, Elassandra has no Single Point Of Write, helping to achieve high availability.
* Elassandra inherits Cassandra data repair mechanisms (hinted handoff, read repair and nodetool repair) providing support for **cross datacenter replication**.
* When adding a node to an Elassandra cluster, only data pulled from existing nodes are re-indexed in OpenSearch.
* Cassandra could be your unique datastore for indexed and non-indexed data. It's easier to manage and secure. Source documents are stored in Cassandra, reducing disk space if you need a NoSQL database and embedded search.
* Write operations are not restricted to one primary shard, but distributed across all Cassandra nodes in a virtual datacenter. The number of shards does not limit your write throughput. Adding elassandra nodes increases both read and write throughput.
* OpenSearch indices can be replicated among many Cassandra datacenters, allowing write to the closest datacenter and search globally.
* The [cassandra driver](http://www.planetcassandra.org/client-drivers-tools/) is Datacenter and Token aware, providing automatic load-balancing and failover.
* Elassandra efficiently stores OpenSearch documents in binary SSTables without any JSON overhead.

## Quick start

* Build a local Docker image with `./gradlew :distribution:docker:buildDockerImage`, then use [`ci/docker-compose.yml`](ci/docker-compose.yml) for a local multi-node demo with the `elassandra:test` image tag.
* Install the maintained Helm chart from [`incloudsio/helm-charts`](https://github.com/incloudsio/helm-charts/tree/master/charts/elassandra). For a local single-node deployment on minikube, start with `helm-charts/charts/elassandra/values-minikube.yaml`.
* The hosted docs remain available at [elassandra.org](https://elassandra.org/en/quickstart.html). Docker packaging remains in this repository, while the Helm chart source now lives in the dedicated chart repository.

### Helm On AKS

The Azure preset now references the pushed Elassandra image at `elassandra.azurecr.io/elassandra:1.3.20`.

Clone the chart repository first:

```bash
git clone https://github.com/incloudsio/helm-charts.git
```

If your AKS cluster is attached to the ACR, install the chart with:

```bash
az aks update \
  --resource-group <resource-group> \
  --name <aks-cluster> \
  --attach-acr elassandra

helm upgrade --install elassandra ./helm-charts/charts/elassandra \
  --namespace elassandra \
  --create-namespace \
  -f ./helm-charts/charts/elassandra/values-azure.yaml
```

If the cluster is not attached to the ACR, create an image pull secret and pass it to the chart:

```bash
kubectl create namespace elassandra

kubectl create secret docker-registry elassandra-acr \
  --namespace elassandra \
  --docker-server=elassandra.azurecr.io \
  --docker-username=<acr-username> \
  --docker-password=<acr-password>

helm upgrade --install elassandra ./helm-charts/charts/elassandra \
  --namespace elassandra \
  -f ./helm-charts/charts/elassandra/values-azure.yaml \
  --set imagePullSecrets[0].name=elassandra-acr
```

To enable OpenSearch Dashboards with the public upstream image, add `--set dashboards.enabled=true`. If you want Dashboards mirrored into ACR as well, push `opensearchproject/opensearch-dashboards:1.3.20` and override `dashboards.image.repository` at install time.

## Older Releases

Older release lines, upgrade notes, and legacy documentation remain available in the historical [strapdata/elassandra](https://github.com/strapdata/elassandra) repository. This repository tracks the current Cassandra 4.0.x + OpenSearch 1.3.x line.

## Installation

For **`modernization/cassandra4-opensearch13`**, use **Java 11** for Gradle and the Cassandra Ant build (`JAVA11_HOME`; see [CONTRIBUTING.md](CONTRIBUTING.md) and CI). Older release branches may still use **Java 8** / **Java 12** as documented there. The **OpenSearch 1.3** search-engine line will stay on **Java 11+** with Cassandra 4.0.

* [Download](https://github.com/incloudsio/elassandra/releases) and extract the distribution tarball
* Define the CASSANDRA_HOME environment variable : `export CASSANDRA_HOME=<extracted_directory>`
* Run `bin/cassandra -f`
* Run `bin/nodetool status`
* Run `curl -XGET localhost:9200/_cluster/state`

#### Example

Try indexing a document on a non-existing index:

```bash
curl -XPUT 'http://localhost:9200/twitter/_doc/1?pretty' -H 'Content-Type: application/json' -d '{
    "user": "Poulpy",
    "post_date": "2017-10-04T13:12:00Z",
    "message": "Elassandra adds dynamic mapping to Cassandra"
}'
```

Then look-up in Cassandra:

```bash
bin/cqlsh -e "SELECT * from twitter.\"_doc\""
```

Behind the scenes, Elassandra has created a new Keyspace `twitter` and table `_doc`.

```CQL
admin@cqlsh>DESC KEYSPACE twitter;

CREATE KEYSPACE twitter WITH replication = {'class': 'NetworkTopologyStrategy', 'DC1': '1'}  AND durable_writes = true;

CREATE TABLE twitter."_doc" (
    "_id" text PRIMARY KEY,
    message list<text>,
    post_date list<timestamp>,
    user list<text>
) WITH bloom_filter_fp_chance = 0.01
    AND caching = {'keys': 'ALL', 'rows_per_partition': 'NONE'}
    AND comment = ''
    AND compaction = {'class': 'org.apache.cassandra.db.compaction.SizeTieredCompactionStrategy', 'max_threshold': '32', 'min_threshold': '4'}
    AND compression = {'chunk_length_in_kb': '64', 'class': 'org.apache.cassandra.io.compress.LZ4Compressor'}
    AND crc_check_chance = 1.0
    AND dclocal_read_repair_chance = 0.1
    AND default_time_to_live = 0
    AND gc_grace_seconds = 864000
    AND max_index_interval = 2048
    AND memtable_flush_period_in_ms = 0
    AND min_index_interval = 128
    AND read_repair_chance = 0.0
    AND speculative_retry = '99PERCENTILE';
CREATE CUSTOM INDEX elastic__doc_idx ON twitter."_doc" () USING 'org.elassandra.index.ExtendedElasticSecondaryIndex';
```

By default, multi valued OpenSearch fields are mapped to Cassandra list.
Now, insert a row with CQL :

```CQL
INSERT INTO twitter."_doc" ("_id", user, post_date, message)
VALUES ( '2', ['Jimmy'], [dateof(now())], ['New data is indexed automatically']);
SELECT * FROM twitter."_doc";

 _id | message                                          | post_date                           | user
-----+--------------------------------------------------+-------------------------------------+------------
   2 |            ['New data is indexed automatically'] | ['2019-07-04 06:00:21.893000+0000'] |  ['Jimmy']
   1 | ['Elassandra adds dynamic mapping to Cassandra'] | ['2017-10-04 13:12:00.000000+0000'] | ['Poulpy']

(2 rows)
```

Then search for it with the OpenSearch API:

```bash
curl "localhost:9200/twitter/_search?q=user:Jimmy&pretty"
```

And here is a sample response :

```JSON
{
  "took" : 3,
  "timed_out" : false,
  "_shards" : {
    "total" : 1,
    "successful" : 1,
    "skipped" : 0,
    "failed" : 0
  },
  "hits" : {
    "total" : {
      "value" : 1,
      "relation" : "eq"
    },
    "max_score" : 0.6931471,
    "hits" : [
      {
        "_index" : "twitter",
        "_type" : "_doc",
        "_id" : "2",
        "_score" : 0.6931471,
        "_source" : {
          "post_date" : [
            "2026-04-17T18:09:37.959Z"
          ],
          "message" : [
            "New data is indexed automatically"
          ],
          "user" : [
            "Jimmy"
          ]
        }
      }
    ]
  }
}
```

By default, Elassandra returns `_source` for both REST-indexed and CQL-indexed documents. To disable it for a specific index, create the index with `"_source": { "enabled": false }` before inserting data.

## Support

* Issues and PRs: [github.com/incloudsio/elassandra](https://github.com/incloudsio/elassandra).
* **Elassandra.org** — project site and coordination.
* **inClouds** — active maintenance and engineering for this fork.
* Historical upstream: [Strapdata](http://www.strapdata.com/), [elassandra Google group](https://groups.google.com/forum/#!forum/elassandra), [github.com/strapdata/elassandra](https://github.com/strapdata/elassandra).

## License

```
This software is licensed under the Apache License, version 2 ("ALv2"), quoted below.

Copyright 2015-2019, Strapdata (contact@strapdata.com).
Copyright 2024-2026 inClouds and contributors.

Licensed under the Apache License, Version 2.0 (the "License"); you may not
use this file except in compliance with the License. You may obtain a copy of
the License at

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS, WITHOUT
WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. See the
License for the specific language governing permissions and limitations under
the License.
```

## Acknowledgments

* Apache Cassandra, Apache Lucene, Apache, Lucene and Cassandra are trademarks of the Apache Software Foundation.
* Elassandra is a trademark of Strapdata SAS. Elassandra.org refers to the community maintenance effort and site for this line.
