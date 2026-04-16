/*
 * Copyright (c) 2017 Strapdata (http://www.strapdata.com)
 * Contains some code from Elasticsearch (http://www.elastic.co)
 *
 * Licensed under the Apache License, Version 2.0 (the "License"); you may not use this file except in compliance with
 * the License. You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */
package org.elassandra;

import org.apache.cassandra.config.DatabaseDescriptor;
import org.apache.cassandra.db.ConsistencyLevel;
import org.opensearch.action.DocWriteResponse;
import org.opensearch.common.xcontent.XContentType;
import org.opensearch.index.query.QueryBuilders;
import org.opensearch.test.OpenSearchSingleNodeTestCase;
import org.junit.Test;

import static org.opensearch.test.hamcrest.OpenSearchAssertions.assertAcked;
import static org.hamcrest.Matchers.equalTo;

public class CqlTypesSubsetTests extends OpenSearchSingleNodeTestCase {

    @Test
    public void testClusteringOrderColumnDiscover() throws Exception {
        process(
            ConsistencyLevel.ONE,
            "CREATE KEYSPACE ks WITH replication = {'class': 'NetworkTopologyStrategy', '"
                + DatabaseDescriptor.getLocalDataCenter()
                + "': 1};"
        );
        process(ConsistencyLevel.ONE, "CREATE TABLE ks.test (id int, timestamp timestamp, PRIMARY KEY (id, timestamp)) WITH CLUSTERING ORDER BY (timestamp DESC)");
        assertAcked(client().admin().indices().prepareCreate("ks").addMapping("test", discoverMapping("test")));
    }

    @Test
    public void testFetchMultipleTypes() throws Exception {
        createIndex("test");
        ensureGreen("test");

        assertThat(client().prepareIndex("test", "typeA", "1").setSource("{ \"a\":\"1\", \"x\":\"aaa\" }", XContentType.JSON).get().getResult(),
            equalTo(DocWriteResponse.Result.CREATED));
        assertThat(client().prepareIndex("test", "typeA", "2").setSource("{ \"b\":\"1\", \"x\":\"aaa\" }", XContentType.JSON).get().getResult(),
            equalTo(DocWriteResponse.Result.CREATED));
        assertThat(client().prepareIndex("test", "typeA", "3").setSource("{ \"c\":\"1\", \"x\":\"aaa\" }", XContentType.JSON).get().getResult(),
            equalTo(DocWriteResponse.Result.CREATED));

        assertThat(client().prepareSearch().setIndices("test").setQuery(QueryBuilders.queryStringQuery("q=aaa")).get().getHits().getTotalHits().value,
            equalTo(3L));
    }
}
