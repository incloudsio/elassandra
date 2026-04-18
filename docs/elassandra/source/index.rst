.. Elassandra documentation master file, created by
   sphinx-quickstart on Sat May 28 19:29:13 2016.
   You can adapt this file completely to your liking, but it should at least
   contain the root `toctree` directive.

Elassandra documentation
========================

*Elassandra* embeds `OpenSearch`_ inside `Cassandra`_ so that each node serves both
distributed storage and distributed search.

The maintained line in this repository targets:

* **Apache Cassandra 4.0.x**
* **OpenSearch 1.3.x**
* **Java 11**

The pages in this guide describe the current OpenSearch-based Elassandra implementation,
its packaging, and its operating model.

   
Contents:

.. toctree::
   :maxdepth: 3

   architecture
   quickstart
   installation
   docker
   helm
   configuration
   mapping
   operations
   search_over_cql
   enterprise
   integration
   testing
   limitations
   migration
   developer/cassandra_fork_inventory
   developer/cassandra_40_rebase
   developer/cassandra_40_jvm_port
   developer/opensearch_porting_guide

Indices and tables
==================

* :ref:`genindex`
* :ref:`modindex`
* :ref:`search`

.. _Cassandra: https://cassandra.apache.org/
.. _OpenSearch: https://opensearch.org/

