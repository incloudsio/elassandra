Operations
==========

Indexing
________

The current Elassandra line accepts OpenSearch-style document indexing while storing the
source-of-truth rows in Cassandra.

For example::

   curl -XPUT 'http://localhost:9200/twitter/_doc/1' \
     -H 'Content-Type: application/json' \
     -d '{
       "user": "kimchy",
       "postDate": "2009-11-15T13:12:00Z",
       "message": "Trying out Elassandra"
     }'

The write is translated into Cassandra mutations and indexed locally on the owning node.

GETing
______

Retrieve a document with the usual OpenSearch API::

   curl -XGET 'http://localhost:9200/twitter/_doc/1?pretty'

Updates
_______

Updates follow the same Cassandra-backed model as indexing. Because Cassandra is the
durable store, conditional uniqueness checks and conflict handling should be designed with
Cassandra semantics in mind. Use lightweight transactions where global conditional write
semantics are required.

Searching
_________

Search requests are routed to the nodes that own the relevant token ranges and merged by
the coordinator::

   curl 'http://localhost:9200/twitter/_search?pretty'

Optimizing search requests
..........................

For predictable latency:

* keep partitions and token ownership balanced
* use targeted indices when possible
* avoid unnecessary field retrieval for large result sets

Caching features
................

Performance comes from a mix of Cassandra caching, Lucene-level caching inside the
embedded OpenSearch runtime, and Elassandra's token-range filter caching. Tune these
based on observed workloads rather than enabling everything by default.

Create, delete and rebuild index
________________________________

Create an index directly::

   curl -XPUT 'http://localhost:9200/twitter'

Create an index backed by an existing Cassandra keyspace::

   curl -XPUT 'http://localhost:9200/twitter_index' \
     -H 'Content-Type: application/json' \
     -d '{
       "settings": {
         "keyspace": "twitter"
       },
       "mappings": {
         "_doc": {
           "discover": "^((?!message).*)",
           "properties": {
             "message": { "type": "keyword", "cql_collection": "singleton" }
           }
         }
       }
     }'

Delete an index without deleting Cassandra data::

   curl -XDELETE 'http://localhost:9200/twitter_index'

Rebuild search structures from Cassandra data when mappings change or after operational
recovery::

   nodetool rebuild_index [--threads <N>] <keyspace> <table> elastic_<table>_idx

Open, close index
_________________

Open and close operations are available through the standard HTTP APIs::

   curl -XPOST 'http://localhost:9200/my_index/_close'
   curl -XPOST 'http://localhost:9200/my_index/_open'

Flush, refresh index
____________________

Refresh controls search visibility, while Cassandra flushes control durable SSTable
materialization::

   curl -XPOST 'http://localhost:9200/my_index/_refresh'
   nodetool flush <keyspace> <table>

Managing Elassandra nodes
_________________________

Use normal Cassandra operational commands for ring membership and topology changes::

   nodetool status
   nodetool cleanup
   nodetool repair

Elassandra will adapt the search routing view as token ownership changes.

Backup and restore
__________________

Because Cassandra is the source of truth, snapshot and restore workflows should start
from Cassandra snapshots and schema backups. Validate index rebuild requirements as part
of the restore runbook.

Restoring a snapshot
....................

Restore Cassandra data and schema first, then rebuild or reopen the affected search
indices if needed.

Point in time recovery
......................

Plan point-in-time recovery around Cassandra commitlog and snapshot capabilities rather
than a separate search-only backup path.

Restoring to a different cluster
................................

When restoring into a fresh cluster, verify:

* keyspace replication
* schema compatibility
* search metadata availability
* successful index rebuilds from restored SSTables

Data migration
______________

Migration into the current OpenSearch-based line is usually done by rebuilding search
from Cassandra data or by reindexing into fresh indices on the target cluster.

Migrating from Cassandra to Elassandra
......................................

Replace the Cassandra binaries with Elassandra, keep the data directories, and then
define the mappings or discovered indices you want to expose.

Migrating from a legacy search-backed line
..........................................

Use the guidance in :doc:`migration`. The current line expects OpenSearch 1.3-era APIs
and Cassandra 4.0 storage behavior.

Tooling
_______

Operational tooling remains Cassandra-first:

* ``nodetool`` for ring, repair, flush, and compaction work
* ``cqlsh`` for schema and data inspection
* OpenSearch-compatible HTTP clients for search and mapping APIs

JMXMP support
.............

JMX access follows Cassandra's JMX configuration and can be integrated with existing JVM
monitoring systems.

Smile decoder
.............

If you use binary payload tooling around the OpenSearch APIs, validate compatibility
against the OpenSearch 1.3 line shipped by this repository.
