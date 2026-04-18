Mapping
=======

In Elassandra, an OpenSearch index is backed by a Cassandra keyspace and the current
document model uses the single ``_doc`` type backed by a Cassandra table.

Type mapping
------------

The most common field mappings are:

.. cssclass:: table-bordered

    +--------------------+---------------------------+------------------------------------------------------------+
    | OpenSearch type    | Cassandra type            | Notes                                                      |
    +====================+===========================+============================================================+
    | ``keyword``        | ``text``                  | Default exact-value string mapping.                        |
    +--------------------+---------------------------+------------------------------------------------------------+
    | ``text``           | ``text``                  | Full-text string mapping.                                  |
    +--------------------+---------------------------+------------------------------------------------------------+
    | ``date``           | ``timestamp`` or ``date`` | Depends on the source schema.                              |
    +--------------------+---------------------------+------------------------------------------------------------+
    | ``integer``        | ``int``                   |                                                            |
    +--------------------+---------------------------+------------------------------------------------------------+
    | ``long``           | ``bigint`` or ``time``    | ``time`` stays a numeric value in the index.               |
    +--------------------+---------------------------+------------------------------------------------------------+
    | ``double``         | ``double``                |                                                            |
    +--------------------+---------------------------+------------------------------------------------------------+
    | ``float``          | ``float``                 |                                                            |
    +--------------------+---------------------------+------------------------------------------------------------+
    | ``boolean``        | ``boolean``               |                                                            |
    +--------------------+---------------------------+------------------------------------------------------------+
    | ``ip``             | ``inet``                  |                                                            |
    +--------------------+---------------------------+------------------------------------------------------------+
    | ``binary``         | ``blob``                  |                                                            |
    +--------------------+---------------------------+------------------------------------------------------------+
    | ``geo_point``      | UDT or text               | Geospatial point mapping.                                  |
    +--------------------+---------------------------+------------------------------------------------------------+
    | ``geo_shape``      | text plus ``_source``     | Keep ``_source`` enabled when original geometry is needed. |
    +--------------------+---------------------------+------------------------------------------------------------+
    | ``object``         | UDT, map, or opaque map   | Structured fields map onto Cassandra composite types.      |
    +--------------------+---------------------------+------------------------------------------------------------+
    | ``nested``         | frozen UDT                | Nested structures require at least one sub-field.          |
    +--------------------+---------------------------+------------------------------------------------------------+

CQL mapper extensions
---------------------

Elassandra adds mapping parameters that control the Cassandra storage model:

.. cssclass:: table-bordered

    +-----------------------------+----------------------------------+------------------------------------------------------------+
    | Parameter                   | Values                           | Purpose                                                    |
    +=============================+==================================+============================================================+
    | ``cql_collection``          | ``list``, ``set``, ``singleton`` | Select how values are stored in Cassandra.                 |
    +-----------------------------+----------------------------------+------------------------------------------------------------+
    | ``cql_struct``              | ``udt``, ``map``, ``opaque_map`` | Control object and nested storage layout.                  |
    +-----------------------------+----------------------------------+------------------------------------------------------------+
    | ``cql_static_column``       | ``true`` or ``false``            | Map a field onto a static Cassandra column.                |
    +-----------------------------+----------------------------------+------------------------------------------------------------+
    | ``cql_primary_key_order``   | integer                          | Place a field into the Cassandra primary key.              |
    +-----------------------------+----------------------------------+------------------------------------------------------------+
    | ``cql_partition_key``       | ``true`` or ``false``            | Mark the field as part of the partition key.               |
    +-----------------------------+----------------------------------+------------------------------------------------------------+
    | ``cql_clustering_key_desc`` | ``true`` or ``false``            | Control clustering-key sort order.                         |
    +-----------------------------+----------------------------------+------------------------------------------------------------+
    | ``cql_udt_name``            | custom name                      | Override the generated UDT name.                           |
    +-----------------------------+----------------------------------+------------------------------------------------------------+
    | ``cql_type``                | custom Cassandra type            | Override inferred Cassandra storage type.                  |
    +-----------------------------+----------------------------------+------------------------------------------------------------+

OpenSearch multi-fields
-----------------------

OpenSearch multi-fields work in Elassandra and are useful when you want one field
indexed in multiple ways, for example as both ``text`` and ``keyword``.

Bi-directional mapping
----------------------

Elassandra supports both schema directions:

* define an OpenSearch mapping and let Elassandra create the Cassandra schema
* create the Cassandra schema first and let Elassandra discover it into a mapping

Discover an existing Cassandra-backed ``_doc`` table::

   curl -XPUT 'http://localhost:9200/my_keyspace/_mapping/_doc' \
     -H 'Content-Type: application/json' \
     -d '{
       "_doc": {
         "discover": "^((?!name).*)",
         "properties": {
           "name": { "type": "text" }
         }
       }
     }'

When creating the first index for a table, Elassandra also creates the backing Cassandra
secondary index structures required for search.

Meta-Fields
-----------

Key meta-fields behave as follows in Elassandra:

* ``_index`` maps to the Cassandra keyspace name
* ``_doc`` is the current document type exposed through the API
* ``_id`` is derived from the Cassandra primary key
* ``_source`` is reconstructed from Cassandra columns unless explicitly stored
* ``_routing`` is derived from the Cassandra partition key
* ``_token`` and ``_host`` are Elassandra-specific helpers for token-aware behavior

Mapping change with zero downtime
---------------------------------

A common zero-downtime workflow is:

#. create a new index with the updated mapping
#. point it at the existing Cassandra keyspace if appropriate
#. rebuild the backing search structures from Cassandra data
#. switch traffic via aliases

For example::

   curl -XPUT 'http://localhost:9200/twitter_v2' \
     -H 'Content-Type: application/json' \
     -d '{
       "settings": { "keyspace": "twitter" },
       "mappings": {
         "_doc": {
           "properties": {
             "message":   { "type": "text" },
             "post_date": { "type": "date" },
             "user":      { "type": "keyword" }
           }
         }
       }
     }'

Then rebuild from Cassandra::

   nodetool rebuild_index [--threads <N>] twitter "_doc" elastic__doc_idx

Partitioned Index
-----------------

Partitioned indices are useful for time-based or very large datasets where you want
multiple logical search indices over Cassandra-backed data. The partition function
selects which index receives each document.

Virtual index
.............

Virtual index patterns let Elassandra route one logical dataset into multiple physical
indices while still using Cassandra as the durable store.

Object and Nested mapping
-------------------------

Objects and nested fields are backed by Cassandra UDTs or maps. Choose the storage mode
based on your schema stability:

* UDTs for well-defined structured documents
* maps for dynamic key sets that still need mapped sub-fields
* opaque maps when keys vary heavily and you do not want per-key schema updates

Dynamic mapping of Cassandra Map
--------------------------------

Dynamic map-backed structures can be indexed directly. If the set of keys grows in an
unbounded way, prefer ``opaque_map`` to avoid excessive schema churn.

Dynamic Template with Dynamic Mapping
.....................................

Combine dynamic templates with Elassandra's discovery support when a Cassandra-first
table should expose a partly controlled but partly evolving schema.

Parent-Child Relationship
-------------------------

Parent-child style relationships depend on careful primary-key design and should be
validated against your actual access patterns. In many cases, denormalized Cassandra
tables or nested structures provide a more predictable operational model.

Indexing Cassandra static columns
---------------------------------

Static columns can be indexed by enabling the related mapping settings:

* ``index_static_document``
* ``index_static_only``
* ``index_static_columns``

These settings control whether Elassandra creates dedicated static-only documents or
merges static columns into ordinary row-backed documents.

Elassandra as a JSON-REST Gateway
---------------------------------

Elassandra exposes Cassandra-backed documents through OpenSearch-compatible HTTP APIs,
which makes it useful as a JSON gateway in front of Cassandra data when search is also
required.

OpenSearch pipeline processors
------------------------------

The current line supports OpenSearch ingest pipelines for supported processors. Use them
when documents should be normalized or enriched before indexing.

Check Cassandra consistency with OpenSearch
-------------------------------------------

Operational consistency checks usually start from Cassandra because it is the source of
truth. When search results appear stale or incomplete:

* verify the Cassandra rows first
* inspect the mapping and index state
* rebuild the index from Cassandra if necessary
