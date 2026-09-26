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
package org.elassandra.index;

import org.apache.cassandra.cql3.UntypedResultSet;
import org.apache.cassandra.db.ConsistencyLevel;
import org.apache.cassandra.db.marshal.Int32Type;
import org.apache.cassandra.service.StorageService;
import org.junit.After;
import org.junit.Before;
import org.junit.Test;
import org.opensearch.index.IndexService;
import org.opensearch.index.query.QueryBuilders;
import org.opensearch.index.shard.IndexShard;
import org.opensearch.test.OpenSearchSingleNodeTestCase;

import java.nio.ByteBuffer;
import java.nio.file.Files;
import java.util.Collections;
import java.util.HashSet;
import java.util.Locale;
import java.util.Set;
import java.util.concurrent.TimeUnit;

import static org.hamcrest.Matchers.equalTo;
import static org.opensearch.test.hamcrest.OpenSearchAssertions.assertAcked;

public class ConsistencyAdversarialTests extends OpenSearchSingleNodeTestCase {

    @Before
    public void clearHooks() {
        ElasticSecondaryIndex.indexParsedDocumentFailureHook = null;
        ElasticSecondaryIndex.truncateTaskFailureHook = null;
    }

    @After
    public void restoreHooks() {
        ElasticSecondaryIndex.indexParsedDocumentFailureHook = null;
        ElasticSecondaryIndex.truncateTaskFailureHook = null;
    }

    private String randomIndexName(String prefix) {
        return (prefix + "_" + randomAlphaOfLength(8)).toLowerCase(Locale.ROOT);
    }

    private IndexService createMappedIndex(String index) throws Exception {
        IndexService indexService = createIndex(index);
        ensureGreen(index);
        process(ConsistencyLevel.ONE, "CREATE TABLE IF NOT EXISTS " + index + ".t1 ( a int, b text, primary key (a) )");
        assertAcked(client().admin().indices().preparePutMapping(index).setType("t1").setSource(discoverMapping("t1")).get());
        return indexService;
    }

    private void assertSearchHitCount(String index, long expected) throws Exception {
        assertBusy(() -> {
            client().admin().indices().prepareRefresh(index).get();
            assertThat(
                client().prepareSearch().setIndices(index).setTypes("t1").setQuery(QueryBuilders.matchAllQuery()).get().getHits().getTotalHits().value,
                equalTo(expected)
            );
        });
    }

    private ElasticSecondaryIndex esi(String index) {
        ElasticSecondaryIndex esi = ElasticSecondaryIndex.elasticSecondayIndices.get(index + ".t1");
        assertNotNull("secondary index missing for " + index + ".t1", esi);
        return esi;
    }

    private ByteBuffer intKey(int a) {
        return Int32Type.instance.decompose(a);
    }

    private Set<Integer> cassandraIds(String index) {
        UntypedResultSet rs = process(ConsistencyLevel.ONE, "SELECT a FROM " + index + ".t1");
        Set<Integer> ids = new HashSet<>();
        rs.forEach(row -> ids.add(row.getInt("a")));
        return ids;
    }

    @Test
    public void testRebuildDoesNotResurrectPurgedRow() throws Exception {
        String index = randomIndexName("ghost");
        createMappedIndex(index);

        process(ConsistencyLevel.ONE, "INSERT INTO " + index + ".t1 (a,b) VALUES (1, 'keep')");
        process(ConsistencyLevel.ONE, "INSERT INTO " + index + ".t1 (a,b) VALUES (2, 'drop')");
        assertSearchHitCount(index, 2L);

        client().admin().indices().prepareClose(index).get();
        process(ConsistencyLevel.ONE, "DELETE FROM " + index + ".t1 WHERE a = 2");
        process(ConsistencyLevel.ONE, "ALTER TABLE " + index + ".t1 WITH gc_grace_seconds = 0");
        StorageService.instance.forceKeyspaceFlush(index, "t1");
        StorageService.instance.forceKeyspaceCompaction(true, index);

        client().admin().indices().prepareOpen(index).get();
        ensureGreen(index);
        StorageService.instance.rebuildSecondaryIndex(index, "t1", "elastic_t1_idx");
        assertTrue(waitIndexRebuilt(index, Collections.singletonList("t1"), 15000));
        assertSearchHitCount(index, 1L);
        assertBusy(() -> {
            client().admin().indices().prepareRefresh(index).get();
            assertThat(
                client().prepareSearch().setIndices(index).setTypes("t1").setQuery(QueryBuilders.termQuery("a", 2)).get().getHits().getTotalHits().value,
                equalTo(0L)
            );
        });
    }

    @Test
    public void testRebuildDuringLiveWritesMatchesCassandra() throws Exception {
        String index = randomIndexName("rebuild_live");
        createMappedIndex(index);
        for (int i = 1; i <= 5; i++) {
            process(ConsistencyLevel.ONE, "INSERT INTO " + index + ".t1 (a,b) VALUES (?,?)", i, "v" + i);
        }
        assertSearchHitCount(index, 5L);

        Thread mutator = new Thread(() -> {
            try {
                process(ConsistencyLevel.ONE, "INSERT INTO " + index + ".t1 (a,b) VALUES (6, 'live')");
                process(ConsistencyLevel.ONE, "DELETE FROM " + index + ".t1 WHERE a = 1");
            } catch (Exception e) {
                throw new RuntimeException(e);
            }
        });
        mutator.start();
        StorageService.instance.rebuildSecondaryIndex(index, "t1", "elastic_t1_idx");
        mutator.join();
        StorageService.instance.forceKeyspaceFlush(index, "t1");

        assertBusy(() -> {
            client().admin().indices().prepareRefresh(index).get();
            Set<Integer> cassandra = cassandraIds(index);
            long hits = client().prepareSearch().setIndices(index).setTypes("t1").setQuery(QueryBuilders.matchAllQuery()).setSize(20)
                .get().getHits().getTotalHits().value;
            assertThat(hits, equalTo((long) cassandra.size()));
        });
    }

    @Test
    public void testFailedIndexLeavesRecoveryRecordAndReplayConverges() throws Exception {
        String index = randomIndexName("fail_idx");
        createMappedIndex(index);
        process(ConsistencyLevel.ONE, "INSERT INTO " + index + ".t1 (a,b) VALUES (1, 'ok')");
        assertSearchHitCount(index, 1L);

        ElasticSecondaryIndex.indexParsedDocumentFailureHook = () -> {
            throw new RuntimeException("injected index failure");
        };
        process(ConsistencyLevel.ONE, "INSERT INTO " + index + ".t1 (a,b) VALUES (2, 'pending')");
        assertTrue(esi(index).hasRecoveryRecord(intKey(2)));
        client().admin().indices().prepareRefresh(index).get();
        assertThat(
            client().prepareSearch().setIndices(index).setTypes("t1").setQuery(QueryBuilders.termQuery("a", 2)).get().getHits().getTotalHits().value,
            equalTo(0L)
        );

        ElasticSecondaryIndex.indexParsedDocumentFailureHook = null;
        esi(index).replayPending();
        assertSearchHitCount(index, 2L);
        StorageService.instance.forceKeyspaceFlush(index, "t1");
        assertBusy(() -> assertThat(esi(index).hasRecoveryRecord(intKey(2)), equalTo(false)));
    }

    @Test
    public void testWriteWhileIndexClosedIsReplayedOnOpen() throws Exception {
        String index = randomIndexName("closed_write");
        createMappedIndex(index);
        process(ConsistencyLevel.ONE, "INSERT INTO " + index + ".t1 (a,b) VALUES (1, 'visible')");
        assertSearchHitCount(index, 1L);

        client().admin().indices().prepareClose(index).get();
        process(ConsistencyLevel.ONE, "INSERT INTO " + index + ".t1 (a,b) VALUES (2, 'deferred')");
        assertTrue(esi(index).hasRecoveryRecord(intKey(2)));

        client().admin().indices().prepareOpen(index).get();
        ensureGreen(index);
        assertSearchHitCount(index, 2L);
        StorageService.instance.forceKeyspaceFlush(index, "t1");
        assertBusy(() -> assertThat(esi(index).hasRecoveryRecord(intKey(2)), equalTo(false)));
    }

    @Test
    public void testTruncateClearsSearch() throws Exception {
        String index = randomIndexName("trunc");
        createMappedIndex(index);
        process(ConsistencyLevel.ONE, "INSERT INTO " + index + ".t1 (a,b) VALUES (1, 'x')");
        process(ConsistencyLevel.ONE, "INSERT INTO " + index + ".t1 (a,b) VALUES (2, 'y')");
        assertSearchHitCount(index, 2L);

        process(ConsistencyLevel.ONE, "TRUNCATE " + index + ".t1");
        assertSearchHitCount(index, 0L);
    }

    @Test
    public void testTruncateCrashReplaysWipe() throws Exception {
        String index = randomIndexName("trunc_crash");
        IndexService indexService = createMappedIndex(index);
        process(ConsistencyLevel.ONE, "INSERT INTO " + index + ".t1 (a,b) VALUES (1, 'x')");
        assertSearchHitCount(index, 1L);

        ElasticSecondaryIndex.truncateTaskFailureHook = () -> {
            throw new RuntimeException("injected truncate failure");
        };
        try {
            process(ConsistencyLevel.ONE, "TRUNCATE " + index + ".t1");
        } catch (Exception ignored) {
            // Cassandra truncate may still succeed; search wipe is interrupted after the first pass.
        }
        IndexShard shard = indexService.getShard(0);
        assertTrue(Files.exists(shard.shardPath().getDataPath().resolve(ElasticSecondaryIndex.TRUNCATE_PENDING_MARKER)));

        ElasticSecondaryIndex.truncateTaskFailureHook = null;
        esi(index).recoverPendingTruncate();
        assertSearchHitCount(index, 0L);
        assertFalse(Files.exists(shard.shardPath().getDataPath().resolve(ElasticSecondaryIndex.TRUNCATE_PENDING_MARKER)));
    }

    @Test
    public void testTtlHidesDocumentWithoutCompaction() throws Exception {
        String index = randomIndexName("ttl");
        createMappedIndex(index);
        process(ConsistencyLevel.ONE, "INSERT INTO " + index + ".t1 (a,b) VALUES (1, 'ephemeral') USING TTL 3");
        assertSearchHitCount(index, 1L);

        assertBusy(() -> {
            UntypedResultSet rs = process(ConsistencyLevel.ONE, "SELECT a FROM " + index + ".t1 WHERE a = 1");
            assertThat(rs.size(), equalTo(0));
        }, 10, TimeUnit.SECONDS);

        assertBusy(() -> {
            client().admin().indices().prepareRefresh(index).get();
            assertThat(
                client().prepareSearch().setIndices(index).setTypes("t1").setQuery(QueryBuilders.matchAllQuery()).get().getHits().getTotalHits().value,
                equalTo(0L)
            );
        }, 10, TimeUnit.SECONDS);
    }
}
