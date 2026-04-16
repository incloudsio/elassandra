# How to contribute

Elassandra now ships an OpenSearch 1.3.x-based search engine integrated directly into Apache Cassandra 4.0.x:
* The **ElassandraDaemon** class extends **CassandraDaemon** in the Cassandra fork and manages OpenSearch bootstrap and node lifecycle.
* The **ElasticSecondaryIndex** class implements the Cassandra **Index** interface and writes into OpenSearch indices.

![Elassandra class inheritance](/docs/elassandra/source/images/elassandra-inheritance.png)

To achieve these operations, the project carries two coordinated codebases:

A fork of [Apache Cassandra](http://git-wip-us.apache.org/repos/asf/cassandra.git) including the Elassandra bootstrap and indexing hooks, maintained at [incloudsio/cassandra](https://github.com/incloudsio/cassandra) (see `server/cassandra` submodule).

The merged **OpenSearch 1.3.x** server tree in this repository, plus the Elassandra bridge code under `server/src/main/java/org/elassandra`, including modifications in:
* Cluster state management and discovery (see [org.elassandra.discovery](/server/src/main/java/org/elassandra/discovery))
* Gateway and bootstrap integration (see [org.elassandra.gateway](/server/src/main/java/org/elassandra/gateway) and [org.apache.cassandra.service.ElassandraDaemon](/server/cassandra/src/java/org/apache/cassandra/service/ElassandraDaemon.java))
* Field mappers and CQL mapping support (see [org.opensearch.index.mapper](/server/src/main/java/org/opensearch/index/mapper) and [org.elassandra.index](/server/src/main/java/org/elassandra/index))
* Search request routing and token-aware execution (see [org.elassandra.cluster.routing](/server/src/main/java/org/elassandra/cluster/routing))

As shown below, the Cassandra fork and the OpenSearch-based server tree can evolve independently and are periodically rebased together for Elassandra.

![Elassandra developpement process](/docs/elassandra/source/images/elassandra-devprocess.png)

Elassandra depends on the Cassandra fork published as **`io.inclouds.cassandra`** (see **buildSrc/version.properties** and [incloudsio/cassandra](https://github.com/incloudsio/cassandra)):
* **buildSrc/version.properties** carries the pinned Cassandra and OpenSearch versions for this branch.
* The **server/cassandra** git submodule points at [incloudsio/cassandra](https://github.com/incloudsio/cassandra) and should match `cassandra=` from `buildSrc/version.properties`.

Contributors may open issues or pull requests on **[Elassandra](https://github.com/incloudsio/elassandra)** and, for Cassandra-fork–specific changes, on **[incloudsio/cassandra](https://github.com/incloudsio/cassandra)**.

## Bug reports

When submitting an issue, please make sure that :

* You are testing against the latest version of Elassandra.
* You're not in the case of a known Elassandra limitation, see http://doc.elassandra.io/en/latest/limitations.html.
* Elassandra behavior is abnormally different from the standard Cassandra or Elasticsearch. For example, like Elasticsearch, Elassandra does not display default mappings unless requested, but this is the expected behavior.

It is very helpful if you can provide a test case to reproduce the bug and the associated error logs or stacktrace. See your **conf/logback.xml** to increase logging level in the **logs/system.log** file, and run **nodetool setlogginglevel** to dynamically update your logging level.

## Feature requests

You're welcome to open an issue on https://github.com/incloudsio/elassandra for new features, describing why and how it should work.

## Contributing code and documentation changes

Contributors can clone repositories and follow guidelines from OpenSearch and Cassandra :
* [Contributing to the OpenSearch codebase](https://github.com/opensearch-project/OpenSearch/blob/main/CONTRIBUTING.md)
* [Cassandra How To Contribute](https://wiki.apache.org/cassandra/HowToContribute)

When cloning Elassandra, use **git clone --recurse-submodules https://github.com/incloudsio/elassandra** to fetch the **server/cassandra** submodule ([incloudsio/cassandra](https://github.com/incloudsio/cassandra)) and ensure the submodule commit matches **buildSrc/version.properties** (`cassandra=`) and `./scripts/check-cassandra-submodule.sh`. You may use your own Cassandra branch if it includes the Elassandra-required changes; see the [Cassandra fork inventory](docs/elassandra/source/developer/cassandra_fork_inventory.rst).

If you cloned without **--recurse-submodules**, run **git submodule update --init** and check out the branch recorded by this repository.

Then, to build from sources:

* Current OpenSearch 1.3 / Cassandra 4.0 line:

      export JAVA11_HOME=/path/to/jdk-11
      export JAVA12_HOME=/path/to/jdk-11
      export JAVA_HOME=/path/to/jdk-11
      ./gradlew clean assemble -Dbuild.snapshot=false

* To exercise the side-car rebase harness against upstream OpenSearch:

      export JAVA_HOME=/path/to/jdk-11
      ./scripts/opensearch-sidecar-compile-try.sh
      ./scripts/opensearch-sidecar-test-try.sh
      
For repository-specific porting context, see `server/OPENSEARCH_PORT.md` and the developer docs under `docs/elassandra/source/developer/`.

Elassandra documentation is based on [sphinx](http://www.sphinx-doc.org/en/stable/rest.html) and published on [readthedoc.org](https://readthedocs.org/). 
Source RestructuredText files are located under [docs/elassandra](docs/elassandra) in this repository.
To build the documentation, just run **make html** from the *${project.dir}/docs/elassandra*.

### Submitting your changes

1. Test you changes

You can build Elassandra single-node unit tests mixing OpenSearch and Cassandra CQL/nodetool requests.
See [Elassandra Testing](http://doc.elassandra.io/en/latest/testing.html) documentation and 
existing Elassandra unit tests under `server/src/test/java/org/elassandra` and related trees.
For multi-node testing, you can use [ecm](https://github.com/strapdata/ecm) (historical fork of [ccm](https://github.com/pcmanus/ccm)) 
running Elassandra.

2. Rebase your changes

Like with OpenSearch, update your local repository with the most recent code from the main Elassandra repository, 
and rebase your branch on top of the latest master branch. We prefer your initial changes to be squashed into a single 
commit. Later, if we ask you to make changes, add them as separate commits. This makes them easier to review. 
As a final step before merging we will either ask you to squash all commits yourself or we'll do it for you.

3. Submit a pull request

Finally, push your local changes to your forked copy of the elassandra repository and [submit a pull request](https://help.github.com/articles/using-pull-requests). In the pull request, choose a title which sums up the changes that you have made, including the issue number (ex: #91 null_value support), and provide details about your changes.

As usual, you should never force push to a publicly shared branch, but add incremental commits.
