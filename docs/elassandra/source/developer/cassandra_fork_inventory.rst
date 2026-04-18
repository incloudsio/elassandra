.. _cassandra_fork_inventory:

Cassandra fork inventory (legacy 3.11 line to Apache 4.0.x)
============================================================

This page records the **Elassandra-specific delta** on top of Apache Cassandra for the
``server/cassandra`` submodule (``https://github.com/incloudsio/cassandra``, branch
``cassandra-3.11.9-elassandra``; historical legacy baseline).

Baseline
--------

The Elassandra release in this repository pins submodule commit ``30a4c30bf0`` on branch
``cassandra-3.11.9-elassandra``. Its **merge-base with Apache ``cassandra-3.11.9``** is
``5ef75dd96cb693e4041e9ecb61a6852276f0eca4`` (Apache tag ``cassandra-3.11.9``).

Commit count on the historical fork after that merge-base: **36 commits** (full ``git log`` below).

Classification of legacy-fork commits
-------------------------------------

**Core Elassandra / indexing (must port to 4.0.x)**

* ``add7b78a37`` CASSANDRA-13270 Add function hooks for Elassandra
* ``0f30e639b5`` CASSANDRA-13271 Reduce lock contention on instance factories
* ``7a922aa609`` CASSANDRA-13269 Snapshot support for custom secondary indices
* ``431d014c06`` Add asynchronous index build method
* ``7d18811fdc`` Improve index rebuild with delayed initial rebuild
* ``29bd3be468`` backport SecondaryIndexManagerTest form v4
* ``6285581fda`` Add support for CQL schema update transaction
* ``80980c08a2`` Change create/alter type/table/index statement for validation on a keyspace metadata
* ``2e59831631`` Add support for extensions in schema
* ``5854d30276`` CQL3Type prepare from a KeyspaceMetadata
* ``abb5120714`` Add inhibited MigrationListeners to avoid loops
* ``383ab736bf`` Add function hook for elassandra decimal support
* ``9c0a172cee`` Legacy fork umbrella commit (review diff)

**Operational / deployment**

* ``067af8625a`` Add schema pull on startup when not joining the cluster
* ``1102c3ab4c`` Add sysprop to stop after commitlog replay
* ``59ff8adc92`` Add JMXMP support
* ``d3c1458f7c`` Add sysprop cassandra.max_name_length for KS/CF name length
* ``b6660d3191`` dislay timeout on nodetool describecluster
* ``1c7a462ef2`` CASSANDRA-12837 Add multi-threaded support to nodetool rebuild_index

**Networking / protocol / resilience**

* ``d9c9290bc4`` Implement a GZip Compression for the ValueVersioned field
* ``8c9f060e4e`` Cache SSLContext to avoid CPU & IO Consumption

**Build / tooling**

* ``6bf6230333`` Add a property to select the java compiler
* ``f510c13bd6`` Add ant target for assembling stress jar without running tests
* ``49b2209307`` remove logback config scan test
* ``bb628947cb`` Update README
* ``794f4fec6a`` fixup dependencies
* ``751e46987d`` Upgrade hppc library to version 0.7.1

**Upstream backports bundled in the legacy fork**

* ``8ff5b7b29a`` CASSANDRA-14582 Add system property to set the cassandra hostId if not yet initialized
* ``ce689d8a13`` CASSANDRA-14581 Allow to subclass QueryProcessor and get the projection clause
* ``098355fb06`` CASSANDRA-13834 Fix JMX InstanceAlreadyExistsException
* ``7fef0e9131`` CASSANDRA-13502 Don't overwrite the DefaultUncaughtExceptionHandler when testing
* ``b4c740ef61`` CASSANDRA-13501 Upgrade some dependencies
* ``ddba8eca98`` CASSANDRA-13500 Fix String default Locale with a javassist transformer

**CQL / tooling UX**

* ``e10a3f26f3`` fix cqlsh help url
* ``2c1325f50a`` fixup cqlsh six.viewkeys issue when having table extensions

**Pluggable functions (may overlap Elassandra hooks)**

* ``e9b6ea0219`` CASSANDRA-13267 Add support for pluggable CQL generic functions

Full ordered list (newest first)
--------------------------------

::

  067af8625a Add schema pull on startup when not joining the cluster
  d9c9290bc4 Implement a GZip Compression for the ValueVersioned field
  8c9f060e4e Cache SSLContext to avoid CPU & IO Consumption
  d3c1458f7c Add sysprop cassandra.max_name_length for KS/CF name length
  1102c3ab4c Add sysprop to stop after commitlog replay
  59ff8adc92 Add JMXMP support
  383ab736bf Add function hook for elassandra decimal support
  49b2209307 remove logback config scan test
  bb628947cb Update README
  431d014c06 Add asynchronous index build method
  6bf6230333 Add a property to select the java compiler
  f510c13bd6 Add ant target for assembling stress jar without running tests
  abb5120714 Add inhibited MigrationListeners to avoid loops
  2e59831631 Add support for extensions in schema
  5854d30276 CQL3Type prepare from a KeyspaceMetadata
  e10a3f26f3 fix cqlsh help url
  2c1325f50a fixup cqlsh six.viewkeys issue when having table extensions
  29bd3be468 backport SecondaryIndexManagerTest form v4
  7d18811fdc Improve index rebuild with delayed initial rebuild
  6285581fda Add support for CQL schema update transaction
  80980c08a2 Change create/alter type/table/index statement for validation on a keyspace metadata
  b6660d3191 dislay timeout on nodetool describecluster
  794f4fec6a fixup dependencies
  9c0a172cee Legacy fork umbrella commit
  751e46987d Upgrade hppc library to version 0.7.1
  8ff5b7b29a CASSANDRA-14582 Add system property to set the cassandra hostId if not yet initialized
  ce689d8a13 CASSANDRA-14581 Allow to subclass QueryProcessor and get the projection clause
  098355fb06 CASSANDRA-13834 Fix JMX InstanceAlreadyExistsException
  7fef0e9131 CASSANDRA-13502 Don't overwrite the DefaultUncaughtExceptionHandler when testing
  b4c740ef61 CASSANDRA-13501 Upgrade some dependencies
  ddba8eca98 CASSANDRA-13500 Fix String default Locale with a javassist transformer
  7a922aa609 CASSANDRA-13269 Snapshot support for custom secondary indices
  0f30e639b5 CASSANDRA-13271 Reduce lock contention on instance factories
  add7b78a37 CASSANDRA-13270 Add function hooks for Elassandra
  e9b6ea0219 CASSANDRA-13267 Add support for pluggable CQL generic functions
  1c7a462ef2 CASSANDRA-12837 Add multi-threaded support to nodetool rebuild_index

Branch design for Cassandra 4.0.x
---------------------------------

#. Create ``cassandra-4.0.x-elassandra`` from Apache ``cassandra-4.0.20`` (or current latest 4.0.x tag).
#. Cherry-pick or replay the **Core Elassandra / indexing** commits first; resolve conflicts against
   Cassandra 4.0’s secondary-index and storage APIs (expect rewrites, not clean picks).
#. Replay operational and CQL extension commits.
#. Ignore or replace legacy-fork-only build hacks with Gradle/Ant layout from Apache 4.0.

**Note:** An older 4.0 beta branch also exists in historical materials; it does **not** share a
recent merge-base with Apache ``cassandra-4.0.20`` in a way that allows a trivial fast-forward.
Treat that branch as historical reference only unless you explicitly recover patches from it.

Verification
------------

After porting:

* ``ElassandraDaemon`` and custom secondary index compile and load.
* Schema extensions and metadata transactions behave as on 3.11.
* ``nodetool rebuild_index`` and snapshot paths used by Elassandra still work.

See :ref:`cassandra_40_rebase` for automated patch export and a 4.0 clone/bootstrap flow.
