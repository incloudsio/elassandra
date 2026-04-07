.. _cassandra_40_jvm_port:

Cassandra 4.0 JVM port (Elassandra integration code)
=====================================================

The default ``server/cassandra`` submodule stays on the **3.11.x** Elassandra line so this repository continues to **compile and ship** the Elasticsearch 6.8 stack. Moving to **Cassandra 4.0** requires updating Java in **this** repo (not only the fork):

#. Run ``scripts/use-cassandra-40-submodule.sh`` — aligns ``buildSrc/version.properties`` ``cassandra=`` with ``server/cassandra/build.xml`` ``base.version`` and checks out ``cassandra-4.0.x-elassandra``.
#. Port Elassandra-specific classes against **4.0 APIs** (types and method signatures differ from 3.11; mechanical rename is not enough).

Representative API shifts (non-exhaustive)
------------------------------------------

* ``org.apache.cassandra.config.CFMetaData`` → ``org.apache.cassandra.schema.TableMetadata`` (and related schema types live under ``org.apache.cassandra.schema``).
* ``org.apache.cassandra.config.ColumnDefinition`` → ``org.apache.cassandra.schema.ColumnMetadata``.
* Secondary index ``Index.indexerFor`` — parameters moved from ``PartitionColumns`` / ``OpOrder.Group`` to ``RegularAndStaticColumns`` / ``WriteContext`` (see upstream ``org.apache.cassandra.index.Index`` in the 4.0 sources).
* ``ExtendedElasticSecondaryIndex.validateOptions`` — prefer the overload taking ``TableMetadata`` when both static methods exist.

Primary touchpoints in this repo
---------------------------------

* ``org.elassandra.index.ElasticSecondaryIndex`` / ``ExtendedElasticSecondaryIndex``
* ``org.elassandra.cluster.SchemaManager``, ``QueryManager``, ``SchemaListener``, ``ColumnDescriptor``
* ``org.elasticsearch.cluster.service.ClusterService`` and metadata services that bridge C* schema to Elasticsearch mappings
* Tests under ``server/src/test/java/org/elassandra/``

After the port compiles, run ``./scripts/check-cassandra-submodule.sh`` and ``./gradlew :server:compileJava`` (JDK **8** for C* / legacy ES tree on this branch, unless you have already rebased the search engine to OpenSearch and raised the minimum Java version).
