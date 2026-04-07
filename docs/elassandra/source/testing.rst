Testing
=======

Elasticsearch (and, on the modernization branch, OpenSearch) ships a testing framework based on `JUnit <https://junit.org/junit4/>`_ and `RandomizedRunner <https://labs.carrotsearch.com/randomizedtesting.html>`_.
Most of these tests run with Elassandra to keep the embedded search engine aligned with upstream behavior.

Testing environnement
---------------------

By default, JUnit creates one instance for each test class and executes each *@Test* method in parallel with many threads. Because Cassandra uses many static variables,
concurrent testing is not possible, so each test is executed sequentially (using a semaphore to serialize tests) on a single node Elassandra cluster listening on localhost, 
see `ESSingleNodeTestCase <https://github.com/incloudsio/elassandra/blob/master/test/framework/src/main/java/org/elasticsearch/test/ESSingleNodeTestCase.java>`_).
Test configuration is located in **server/src/test/resources/conf**; data and logs are generated under **server/build** when running Gradle tests.

Between each test, all indices (and underlying keyspaces and tables) are removed to have idempotent testings and avoid conflicts with index names.
System settings ``es.synchronous_refresh`` and ``es.drop_on_delete_index`` are often set to *true* for tests (see Gradle test configuration for this branch).

Finally, the testing framework randomizes the local settings representing a specific geographical, political, or cultural region, but Apache Cassandra does not
support such setting because string manipulation are implemented with the default locale settings (see CASSANDRA-12334).
For exemple, *String.format("SELECT %s FROM ...",...)* is computed as *String.format(Local.getDefault(),"SELECT %s FROM ...",...)*, involving errors for some Locale setting.
As a workaround, a javassit byte-code manipulation in the Ant build step adds a *Locale.ROOT* argument to weak the method calls in all Cassandra classes.

Elassandra build tests
----------------------

Elassandra build unit tests allows using both the Elasticsearch API and CQL requests as shown in the following example.

.. code::
   
   public class BasicTests extends ESSingleNodeTestCase {
   
       @Test
       public void testTest() throws Exception {
        createIndex("cmdb");
        ensureGreen("cmdb");
        
        process(ConsistencyLevel.ONE,"CREATE TABLE cmdb.server ( name text, ip inet, netmask int, prod boolean, primary key (name))");
        assertAcked(client().admin().indices().preparePutMapping("cmdb")
                .setType("server")
                .setSource("{ \"server\" : { \"discover\" : \".*\", \"properties\": { \"name\":{ \"type\":\"keyword\" }}}}")
                .get());
        
        process(ConsistencyLevel.ONE,"insert into cmdb.server (name,ip,netmask,prod) VALUES ('localhost','127.0.0.1',8,true)");
        process(ConsistencyLevel.ONE,"insert into cmdb.server (name,ip,netmask,prod) VALUES ('my-server','123.45.67.78',24,true)");
        
        assertThat(client().prepareGet().setIndex("cmdb").setType("server").setId("my-server").get().isExists(), equalTo(true));
        assertThat(client().prepareGet().setIndex("cmdb").setType("server").setId("localhost").get().isExists(), equalTo(true));
        
        assertEquals(client().prepareIndex("cmdb", "server", "bigserver234")
            .setSource("{\"ip\": \"22.22.22.22\", \"netmask\":32, \"prod\" : true, \"description\": \"my big server\" }")
            .get().getResult(), DocWriteResponse.Result.CREATED);
        
        assertThat(client().prepareSearch().setIndices("cmdb").setTypes("server").setQuery(QueryBuilders.queryStringQuery("*:*")).get().getHits().getTotalHits(), equalTo(3L));
       }
   }

To run this specific test :

.. code::

   ./gradlew :server:test -Dtests.seed=96A0B026F3E89763 -Dtests.class=org.elassandra.BasicTests -Dtests.security.manager=false -Dtests.locale=it-IT -Dtests.timezone=Asia/Tomsk

To run all server unit tests :

.. code::

   ./gradlew :server:test


Application tests with Elassandra-Unit
--------------------------------------

`Elassandra-Unit <https://github.com/strapdata/elassandra-unit>`_ helps you writing isolated JUnit tests in a Test Driven Development style with an embedded Elassandra instance.

.. image:: images/elassandra-unit.png

* Start an embedded Elassandra (including both Cassandra and Elasticsearch).
* Create structure (keyspace and Column Families) and load data from an XML, JSON or YAML DataSet.
* Execute a CQL script.
* Query Cassandra through the `Cassandra driver <https://github.com/datastax/java-driver>`_.
* Query the embedded search engine through the `Elasticsearch Java REST client <https://www.elastic.co/guide/en/elasticsearch/client/java-rest/6.8/java-rest-high.html>`_ (6.8 line) or, after the OpenSearch port, the `OpenSearch Java client <https://opensearch.org/docs/latest/clients/java/>`_.

See the `Elassandra-Unit <https://github.com/strapdata/elassandra-unit>`_ README for more information.