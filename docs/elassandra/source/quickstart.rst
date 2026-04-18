Quick Start
===========

Start your cluster
------------------

Build the local Docker image and start the repository's example multi-node cluster::

    ./gradlew :distribution:docker:buildDockerImage
    docker-compose -f ci/docker-compose.yml up -d --scale node=0
    docker-compose -f ci/docker-compose.yml up -d --scale node=1

Check the node status::

    docker exec -i test_seed_node_1 nodetool status
    docker exec -i test_seed_node_1 curl -s localhost:9200/

The bundled compose file also starts OpenSearch Dashboards on ``http://localhost:5601``.

Import sample data
------------------

Index a sample document through the OpenSearch API::

    curl -XPUT 'http://localhost:9200/twitter/_doc/1?pretty' \
      -H 'Content-Type: application/json' \
      -d '{
        "user": "Poulpy",
        "post_date": "2017-10-04T13:12:00Z",
        "message": "Elassandra adds dynamic mapping to Cassandra"
      }'

Elassandra automatically creates the ``twitter`` keyspace and the backing ``"_doc"`` table.

Create an OpenSearch index from a Cassandra table
-------------------------------------------------

Create a keyspace and a table first::

   docker exec -i test_seed_node_1 cqlsh <<'EOF'
   CREATE KEYSPACE IF NOT EXISTS test
     WITH replication = {'class': 'NetworkTopologyStrategy', 'DC1': 1};
   CREATE TABLE IF NOT EXISTS test."_doc" (
     "_id" text PRIMARY KEY,
     login text,
     first text,
     last text
   );
   INSERT INTO test."_doc" ("_id", login, first, last) VALUES ('1', 'vroyer', 'vince', 'royer');
   INSERT INTO test."_doc" ("_id", login, first, last) VALUES ('2', 'barth', 'barthelemy', 'delemotte');
   EOF

Discover the CQL schema as an OpenSearch mapping::

   curl -XPUT 'http://localhost:9200/test/_mapping/_doc' \
     -H 'Content-Type: application/json' \
     -d '{
       "_doc": {
         "discover": ".*",
         "properties": {
           "login": { "type": "keyword", "cql_collection": "singleton" }
         }
       }
     }'

Create an OpenSearch index from scratch
---------------------------------------

Elassandra can also create the backing Cassandra schema when you define a mapping first::

   curl -XPUT 'http://localhost:9200/twitter2' \
     -H 'Content-Type: application/json' \
     -d '{
       "mappings": {
         "_doc": {
           "properties": {
             "first": { "type": "text" },
             "last":  { "type": "keyword", "cql_collection": "singleton" }
           }
         }
       }
     }'

The generated Cassandra schema uses the OpenSearch document id as the Cassandra primary key::

   docker exec -i test_seed_node_1 cqlsh -e 'DESC KEYSPACE twitter2'

Search for a document
---------------------

Search through the OpenSearch HTTP API::

   curl 'http://localhost:9200/test/_search?pretty'

Typical response::

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
         "value" : 2,
         "relation" : "eq"
       },
       "hits" : [
         {
           "_index" : "test",
           "_type" : "_doc",
           "_id" : "1",
           "_source" : {
             "login" : "vroyer",
             "first" : "vince",
             "last" : "royer"
           }
         }
       ]
     }
   }

You can also search through CQL after adding the Elassandra query columns::

   docker exec -i test_seed_node_1 cqlsh <<'EOF'
   ALTER TABLE test."_doc" ADD es_query text;
   ALTER TABLE test."_doc" ADD es_options text;
   SELECT "_id", login, first, last
   FROM test."_doc"
   WHERE es_query='{ "query":{"term":{"login":"barth"}} }'
     AND es_options='indices=test'
   ALLOW FILTERING;
   EOF

Manage indices
--------------

Inspect index state::

   curl 'http://localhost:9200/_cluster/state?pretty'
   curl 'http://localhost:9200/_cat/indices?v'

Delete an index without deleting the underlying Cassandra table::

   curl -XDELETE 'http://localhost:9200/test'

Cleanup the cluster
-------------------

Stop the local environment::

    docker-compose -f ci/docker-compose.yml stop

Docker troubleshooting
----------------------

Each Elassandra node usually needs around 1.5 GB to 2 GB of RAM for local demos.
If a container exits with status ``137``, Docker likely killed the JVM for exceeding
its memory limit. Increase Docker's memory quota or reduce the heap values in
``ci/docker-compose.yml``.