Search through CQL
==================

Executing OpenSearch queries through the Cassandra CQL driver lets applications reuse
their existing Cassandra connectivity while still accessing Elassandra search features.

Benefits include:

* no separate HTTP load balancer for simple driver-based search flows
* shared Cassandra authentication and TLS handling
* access to Cassandra paging together with search requests

Configuration
.............

Enable the Elassandra query handler and add the query columns to the target table::

   JVM_OPTS="$JVM_OPTS -Dcassandra.custom_query_handler_class=org.elassandra.index.ElasticQueryHandler"

   ALTER TABLE twitter."_doc" ADD es_query text;
   ALTER TABLE twitter."_doc" ADD es_options text;

Search request through CQL
..........................

Once enabled, search requests can be issued directly from CQL::

   SELECT "_id", user, message
   FROM twitter."_doc"
   WHERE es_query='{"query":{"query_string":{"query":"message:dynamic"}}}';

If the target index name differs from the keyspace name, specify it in ``es_options`` and
use ``ALLOW FILTERING``::

   SELECT "_id", user, message
   FROM twitter."_doc"
   WHERE es_query='{"query":{"term":{"user":"Poulpy"}}}'
     AND es_options='indices=twitter'
   ALLOW FILTERING;

Paging
......

When Cassandra driver paging is enabled, Elassandra uses a search scroll internally for
multi-page result sets. If you only need the first few hits, use ``LIMIT`` so the
coordinator can keep the search request small::

   SELECT "_id", user
   FROM twitter."_doc"
   WHERE es_query='{"query":{"match_all":{}}}'
   LIMIT 10;

Routing
.......

Because Elassandra maps search data onto Cassandra token ownership, routing decisions are
based on the Cassandra primary key and partition key model. Keep that relationship in
mind when designing ids and partitions for search-heavy tables.

CQL Functions
.............

Applications that already consume Cassandra result metadata can also inspect the incoming
payload returned by Elassandra to read search metadata such as total hits and shard
status.

Elassandra aggregations through CQL
...................................

Aggregations can be executed through the same ``es_query`` mechanism. The aggregation
response is returned through the query payload rather than regular CQL columns, which
makes this mode best suited to application code rather than interactive shell use.

Application unit tests
......................

For current application-level testing, prefer the repository Docker or Helm workflows and
run CQL search queries against a real Elassandra node with
``org.elassandra.index.ElasticQueryHandler`` enabled.

CQL tracing
...........

When troubleshooting search over CQL, enable Cassandra tracing to inspect the underlying
row fetches and coordinator work::

   tracing on;
   SELECT "_id"
   FROM twitter."_doc"
   WHERE es_query='{"query":{"match_all":{}}}'
   LIMIT 1;
