# How to contribute

Elassandra is based on a fork of Elasticsearch acting as a plugin for Apache Cassandra :
* The **ElassandraDaemon** class override the **CassandraDaemon** class in order to manage Elasticsearch internal services.
* The **ElasticSecondaryIndex** class implements the Cassandra **Index** interface to write in Elasticsearch indices.

![Elassandra class inheritance](/docs/elassandra/source/images/elassandra-inheritance.png)

To achieve these operations, both Cassandra and Elasticsearch requires some modifications located in two forks:

A fork of [Apache Cassandra](http://git-wip-us.apache.org/repos/asf/cassandra.git) including slight modifications, maintained at [incloudsio/cassandra](https://github.com/incloudsio/cassandra) (see `server/cassandra` submodule).

A fork of Elasticsearch 5.5.0 (aka Strapdata-Elasticsearch, branch *${version}-strapdata*) including modifications in :
* Cluster state management ([org.elassandra.cluster.InternalCassandraClusterService](/core/src/main/java/org/elassandra/cluster/InternalCassandraClusterService.java) override a modified [org.elasticsearch.cluster.service.InternalClusterService](/core/src/main/java/org/elasticsearch/cluster/service/InternalClusterService.java))
* Gateway to retrieve Elasticsearch metadata on startup (see [org.elassandra.gateway](/core/src/main/java/org/elassandra/gateway/CassandraGatewayService.java))
* Discovery to manage alive cluster members (see [org.elassandra.discovery.CassandraDiscovery](/core/src/main/java/org/elassandra/discovery/CassandraDiscovery.java))
* Fields mappers to manage CQL mapping and Lucene field factory (see [org.elasticsearch.index.mapper.core](/core/src/main/java/org/elasticsearch/index/mapper/core))
* Search requests routing (see [org.elassandra.cluster.routing](/core/src/main/java/org/elassandra/cluster/routing))

As shown below, forked Cassandra and Elasticsearch projects can change independently and changes can be rebased periodically into Strapdata-Cassandra or Elassandra (aka Strapdata-Elasticsearch).

![Elassandra developpement process](/docs/elassandra/source/images/elassandra-devprocess.png)

Elassandra depends on the Cassandra fork published as **`io.inclouds.cassandra`** (see **buildSrc/version.properties** and [incloudsio/cassandra](https://github.com/incloudsio/cassandra)):
* Elassandra version 5+ **core/pom.xml** includes a Maven dependency on that artifact.
* Elassandra version 6+ **buildSrc/version.properties** includes the Gradle dependency.
* The **server/cassandra** git submodule points at [incloudsio/cassandra](https://github.com/incloudsio/cassandra) (branch **`cassandra-3.11.9-elassandra`** for the current line).

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

Contributors can clone repositories and follow guidelines from Elasticsearch and Cassandra :
* [Contributing to the elasticsearch codebase](https://github.com/elastic/elasticsearch/blob/2.4/CONTRIBUTING.md#contributing-to-the-elasticsearch-codebase)
* [Cassandra How To Contribute](https://wiki.apache.org/cassandra/HowToContribute)

When cloning Elassandra, use **git clone --recurse-submodules https://github.com/incloudsio/elassandra** to fetch the **server/cassandra** submodule ([incloudsio/cassandra](https://github.com/incloudsio/cassandra)) and ensure the submodule commit matches **buildSrc/version.properties** (`cassandra=`) and `./scripts/check-cassandra-submodule.sh`. You may use your own Cassandra branch if it includes the Elassandra-required changes; see the [Cassandra fork inventory](docs/elassandra/source/developer/cassandra_fork_inventory.rst).

If you cloned without **--recurse-submodules**, run **git submodule update --init** and check out the branch recorded by this repository (e.g. **cassandra-3.11.9-elassandra**).

Then, to build from sources: 

* Elassandra v5.x:

      gradle clean assemble -Dbuild.snapshot=false
    
    
* Elassandra v6.2.x:
      
      export JAVA_HOME=/path/to/jdk-10
      export CASSANDRA_JAVA_HOME=/path/to/jdk-8
      ./gradlew clean assemble -Dbuild.snapshot=false

* Elassandra v6.8.x:
      
      export JAVA8_HOME=/path/to/jdk-8
      export JAVA9_HOME=/path/to/jdk-9
      export JAVA12_HOME=/path/to/jdk-12
      export JAVA_HOME=/path/to/jdk-12
      export CASSANDRA_JAVA_HOME=/path/to/jdk-8
      ./gradlew clean assemble -Dbuild.snapshot=false
      
Note: For elassandra v6.X, javadoc task failed due to [https://bugs.java.com/bugdatabase/view_bug.do?bug_id=8194281](https://bugs.java.com/bugdatabase/view_bug.do?bug_id=8194281).

Elassandra documentation is based on [sphinx](http://www.sphinx-doc.org/en/stable/rest.html) and published on [readthedoc.org](https://readthedocs.org/). 
Source RestructuredText files are located under [docs/elassandra](docs/elassandra) in this repository.
To build the documentation, just run **make html** from the *${project.dir}/docs/elassandra*.

### Submitting your changes

1. Test you changes

You can build Elassandra single-node unit tests mixing Elasticsearch and Cassandra CQL/nodetool requests. 
See [Elassandra Testing](http://doc.elassandra.io/en/latest/testing.html) documentation and 
existing Elassandra unit tests under `server/src/test/java/org/elassandra` and related trees.
For multi-node testing, you can use [ecm](https://github.com/strapdata/ecm) (historical fork of [ccm](https://github.com/pcmanus/ccm)) 
running Elassandra.

2. Rebase your changes

Like with Elasticsearch, update your local repository with the most recent code from the main Elassandra repository, 
and rebase your branch on top of the latest master branch. We prefer your initial changes to be squashed into a single 
commit. Later, if we ask you to make changes, add them as separate commits. This makes them easier to review. 
As a final step before merging we will either ask you to squash all commits yourself or we'll do it for you.

3. Submit a pull request

Finally, push your local changes to your forked copy of the elassandra repository and [submit a pull request](https://help.github.com/articles/using-pull-requests). In the pull request, choose a title which sums up the changes that you have made, including the issue number (ex: #91 null_value support), and provide details about your changes.

As usual, you should never force push to a publicly shared branch, but add incremental commits.
