
.. important:: Cassandra and Elassandra packages conflict. Remove any standalone Cassandra package before installing Elassandra.

Install Java 11 first if your distribution does not already provide it::

  sudo apt-get update
  sudo apt-get install openjdk-11-jre-headless

Download the Debian package from the current GitHub release and install it locally::

  curl -LO |deb_url|
  sudo apt-get install ./elassandra-|release|.deb

Start Elassandra with Systemd::

  sudo systemctl start cassandra

or SysV::

  sudo service cassandra start

Files locations:

- ``/usr/bin``: startup script, cqlsh, nodetool, opensearch-plugin
- ``/etc/cassandra`` and ``/etc/default/cassandra``: configurations
- ``/var/lib/cassandra``: data
- ``/var/log/cassandra``: logs
- ``/usr/share/cassandra``: plugins, modules, libs, ...
- ``/usr/share/cassandra/tools``: cassandra-stress, sstabledump...
- ``/usr/lib/python3/dist-packages/cqlshlib/`` or distribution-specific site-packages: python library for cqlsh
