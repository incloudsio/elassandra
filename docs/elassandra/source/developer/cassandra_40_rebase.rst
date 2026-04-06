.. _cassandra_40_rebase:

Cassandra 4.0.x porting playbook
==================================

This is a **practical sequence** for moving Elassandra-specific Cassandra changes from the
**3.11.9** Strapdata line toward **Apache Cassandra 4.0.x**. It complements
:ref:`cassandra_fork_inventory`.

Prerequisites
-------------

* ``server/cassandra`` submodule checked out (same commit as ``cassandra=`` in ``buildSrc/version.properties``).
* **Java 11** for Cassandra 4.0 builds (see Apache Cassandra 4.0 release notes).
* Enough disk for a second Cassandra tree (clone or worktree).

Step 1 — Export patch series (3.11 delta)
-----------------------------------------

From the **Elassandra** repository root:

.. code-block:: bash

   ./scripts/export-cassandra-elassandra-patches.sh

This adds an ``apache`` remote inside ``server/cassandra`` if needed, fetches tag **cassandra-3.11.9**,
computes the merge-base with **HEAD**, and writes ``git format-patch`` files under
``build/cassandra-elassandra-patches/`` (gitignored).

Step 2 — Bootstrap Apache 4.0 tree
----------------------------------

.. code-block:: bash

   ./scripts/bootstrap-cassandra-40-worktree.sh

Defaults clone **Apache Cassandra** at tag **cassandra-4.0.20** into ``../cassandra-4.0-elassandra``
and creates branch ``cassandra-4.0.x-elassandra``. Override with:

* ``CASSANDRA_40_CLONE_DIR`` — destination path
* ``CASSANDRA_APACHE_TAG`` — e.g. ``cassandra-4.0.20``
* ``CASSANDRA_40_BRANCH`` — local branch name

Step 3 — Apply patches on 4.0
-----------------------------

.. code-block:: bash

   cd ../cassandra-4.0-elassandra   # or your CASSANDRA_40_CLONE_DIR
   git am --3way /path/to/elassandra/build/cassandra-elassandra-patches/*.patch

Patch **0001** (CASSANDRA-12837, multi-threaded ``rebuild_index``) does not apply cleanly with ``git am`` on 4.0 because
the index builder stack changed. An equivalent port is maintained on branch ``cassandra-4.0.x-elassandra`` in a local
clone (commit message *Elassandra: port CASSANDRA-12837…*). Reuse or cherry-pick that commit before applying patches
**0002** onward, or continue manual porting.

**Progress note (ongoing):** On a ``cassandra-4.0.20``-based branch, patches **0002–0003**, **0005–0006**, **0008–0009** have been
applied with manual conflict resolution (4.0 APIs and ``build.xml`` layout). Patch **0004** was **skipped** (instance-factory
interning already matches the intent in upstream 4.0). Patch **0007** was **skipped** (bundled ``lib/*.jar`` upgrades are
obsolete for 4.0’s resolver layout). The **javassist** ``transform`` target from **0006** is wired to ``_main-jar`` via
``depends="transform"``; Guava/Javassist jars on the task classpath use ``${build.dir.lib}`` globs rather than fixed
filenames. Remaining patches **0010–0036** still need ``git am --3way`` and porting.

Almost every remaining patch may **conflict** or **fail to compile** on 4.0. Resolve in order:

#. Secondary index / ``Index`` SPI / ``SecondaryIndexManager`` (highest risk).
#. CQL schema extensions and metadata transactions.
#. Gossip / messaging / ``ElassandraDaemon`` hooks (paths moved between 3.11 and 4.0).
#. Build system (Apache 4.0 may prefer Maven for main build; align with upstream layout).

Use ``git am --abort`` if a patch series is unrecoverable; switch to **manual cherry-pick** of the
commits listed in :ref:`cassandra_fork_inventory`.

Step 4 — Publish fork and submodule
-----------------------------------

When the 4.0 tree builds and tests pass:

#. Push **your** fork (e.g. ``github.com/elassandra/cassandra``) on branch ``cassandra-4.0.x-elassandra``.
#. Point Elassandra’s ``.gitmodules`` ``server/cassandra`` URL at that fork and update the submodule SHA.
#. Update ``buildSrc/version.properties`` ``cassandra=`` to match ``build.xml`` ``base.version`` in the new submodule.
#. Run ``./scripts/check-cassandra-submodule.sh`` before release.

Step 5 — Elassandra JVM integration
-----------------------------------

After ``cassandra-all`` publishes with the new coordinates, rebuild **this** repo and fix
``ElasticSecondaryIndex`` / ``ElassandraDaemon`` against any 4.0 API changes (often in parallel with
the OpenSearch port — see :ref:`opensearch_porting_guide`).
