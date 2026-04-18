Breaking changes and limitations
================================

.. note::

   The current repository line embeds **OpenSearch 1.3.x** inside **Apache Cassandra 4.0.x**.
   Older pre-OpenSearch lines are historical and are not described here.

Deleting an index does not delete Cassandra data
------------------------------------------------

By default, Cassandra is the source of truth. Deleting an index removes the search
metadata and search files, but it does not remove the backing keyspace or table unless
``drop_on_delete_index`` is enabled.

Nested or object types cannot be empty
--------------------------------------

Nested and object mappings are backed by Cassandra composite types and therefore must
contain at least one mapped sub-field.

Document version metadata is not meaningful for global consistency
------------------------------------------------------------------

Elassandra relies on Cassandra replication rather than primary-shard sequencing.
As a result, document version metadata such as ``_version``, ``_seq_no``, and
``_primary_term`` should not be treated as globally authoritative conflict controls.

Use Cassandra lightweight transactions when your application needs strict conditional
write behavior.

Index and table naming
----------------------

OpenSearch index names are mapped onto Cassandra keyspace names. Characters that are not
valid for Cassandra identifiers are normalized during schema creation.

Column names
------------

A field name shared across documents in the same index must resolve to a compatible
mapping and Cassandra storage type.

Null values
-----------

Cassandra and OpenSearch treat null and empty collections differently. If your queries
depend on explicit null semantics, validate the mapping behavior carefully before using
that field in production search logic.

Refresh behavior
----------------

Refresh scheduling is decoupled from Cassandra replication. Immediate visibility after a
write is therefore a trade-off between write latency and search freshness. Use
``synchronous_refresh`` only where the extra cost is justified.

Unsupported or reduced-scope features
-------------------------------------

The current Elassandra line intentionally focuses on the embedded OpenSearch use case.
Validate advanced upstream features carefully before depending on them in production,
especially when they assume standalone search-cluster behavior instead of Cassandra-owned
replication and storage.

Cassandra limitations
---------------------

* Elassandra requires the murmur3 partitioner.
* Search indexing adds work to Cassandra writes, especially for complex documents.
* Metadata updates rely on quorum for the Elassandra metadata keyspace.
* ``TRUNCATE`` on an indexed table has search-side consequences and should be treated as
  an operationally significant action.
