Testing
=======

Elassandra uses the in-tree OpenSearch test framework together with Cassandra-aware
test setup so that storage and search behavior can be validated together.

Testing environment
-------------------

The single-node test harness serializes tests because Cassandra relies on static
process-wide state. Test configuration lives under ``server/src/test/resources/conf``
and generated data and logs are written under ``server/build``.

Between tests, indices and their backing keyspaces or tables are cleaned up so that
test runs remain repeatable.

Elassandra build tests
----------------------

The repository contains both unit and integration-style tests that exercise:

* Cassandra schema creation and writes
* OpenSearch indexing and search
* Elassandra-specific mapping and routing behavior
* CQL search via ``org.elassandra.index.ElasticQueryHandler``

Run the full server test suite with::

   ./gradlew :server:test

Run a focused class with the standard test filters::

   ./gradlew :server:test -Dtests.class=<fully.qualified.TestClass>

For current build requirements, use Java 11 and ensure ``JAVA11_HOME`` is set when
the Gradle build expects it.

Application testing
-------------------

For application-level testing, the most reliable options for the current line are:

* spin up the repository Docker image or ``ci/docker-compose.yml`` locally
* deploy the maintained Helm chart into a temporary Kubernetes environment
* point OpenSearch-compatible REST clients and Cassandra drivers at that test cluster

This matches the way the current repository is packaged and avoids relying on older
test harnesses that were built for pre-OpenSearch lines.