/*
 * Licensed to Elasticsearch under one or more contributor
 * license agreements. See the NOTICE file distributed with
 * this work for additional information regarding copyright
 * ownership. Elasticsearch licenses this file to you under
 * the Apache License, Version 2.0 (the "License"); you may
 * not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *    http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing,
 * software distributed under the License is distributed on an
 * "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
 * KIND, either express or implied.  See the License for the
 * specific language governing permissions and limitations
 * under the License.
 */

package org.elassandra.cluster;

import com.carrotsearch.hppc.cursors.ObjectCursor;
import com.google.common.collect.ArrayListMultimap;
import com.google.common.collect.ListMultimap;

import org.apache.cassandra.config.DatabaseDescriptor;
import org.apache.cassandra.locator.InetAddressAndPort;
import org.apache.cassandra.locator.NetworkTopologyStrategy;
import org.apache.cassandra.schema.KeyspaceMetadata;
import org.apache.cassandra.schema.Schema;
import org.apache.cassandra.schema.SchemaChangeListener;
import org.apache.cassandra.schema.TableMetadata;
import org.apache.cassandra.utils.FBUtilities;
import org.apache.logging.log4j.LogManager;
import org.apache.logging.log4j.Logger;
import org.elassandra.index.ElasticSecondaryIndex;
import org.elasticsearch.cluster.ClusterChangedEvent;
import org.elasticsearch.cluster.ClusterState;
import org.elasticsearch.cluster.ClusterStateListener;
import org.elasticsearch.cluster.ClusterStateTaskConfig.SchemaUpdate;
import org.elasticsearch.cluster.ClusterStateUpdateTask;
import org.elasticsearch.cluster.block.ClusterBlocks;
import org.elasticsearch.cluster.metadata.IndexMetaData;
import org.elasticsearch.cluster.metadata.MetaData;
import org.elasticsearch.cluster.routing.RoutingTable;
import org.elasticsearch.cluster.service.ClusterService;
import org.elasticsearch.common.Priority;
import org.elasticsearch.common.settings.Settings;

import java.nio.ByteBuffer;
import java.util.Map;

/**
 * Listen for cassandra schema changes and elasticsearch cluster state changes.
 */
public class SchemaListener extends SchemaChangeListener implements ClusterStateListener
{
    final ClusterService clusterService;
    final Logger logger;

    MetaData recordedMetaData = null;
    final ListMultimap<String, IndexMetaData> recordedIndexMetaData = ArrayListMultimap.create();

    public SchemaListener(Settings settings, ClusterService clusterService) {
        this.clusterService = clusterService;
        this.clusterService.addListener(this);
        this.logger = LogManager.getLogger(getClass());
    }

    /**
     * Apply pending mapping updates to Elasticsearch cluster state (Cassandra 4 uses per-change callbacks; we flush after each table change).
     */
    private void flushTransaction() {
        if (recordedMetaData != null || !recordedIndexMetaData.isEmpty()) {
            final ClusterState currentState = this.clusterService.state();
            final ClusterBlocks.Builder blocks = ClusterBlocks.builder().blocks(currentState.blocks());
            final MetaData sourceMetaData = (recordedMetaData == null) ? currentState.metaData() : recordedMetaData;
            final MetaData.Builder metaDataBuilder = MetaData.builder(sourceMetaData);
            if (recordedMetaData == null) {
                recordedIndexMetaData.keySet().forEach( i -> clusterService.mergeIndexMetaData(metaDataBuilder, i, recordedIndexMetaData.get(i)));
            } else {
                clusterService.mergeWithTableExtensions(metaDataBuilder);
            }

            if (sourceMetaData.settings().getAsBoolean("cluster.blocks.read_only", false))
                blocks.addGlobalBlock(MetaData.CLUSTER_READ_ONLY_BLOCK);

            for (IndexMetaData indexMetaData : sourceMetaData)
                blocks.updateBlocks(indexMetaData);

            final MetaData targetMetaData = metaDataBuilder.build();

            clusterService.submitStateUpdateTask("cql-schema-mapping-update", new ClusterStateUpdateTask(Priority.URGENT) {
                @Override
                public ClusterState execute(ClusterState currentState) {
                    final ClusterState.Builder newStateBuilder = ClusterState.builder(currentState);
                    ClusterState newClusterState = newStateBuilder.incrementVersion()
                        .metaData(clusterService.addVirtualIndexMappings(targetMetaData))
                        .blocks(blocks)
                        .build();
                    newClusterState = ClusterState.builder(newClusterState)
                            .routingTable(RoutingTable.build(SchemaListener.this.clusterService, newClusterState))
                            .build();
                    return newClusterState;
                }

                @Override
                public void onFailure(String source, Exception t) {
                    logger.error("unexpected failure during [{}]", t, source);
                }

                @Override
                public SchemaUpdate schemaUpdate() {
                    return SchemaUpdate.UPDATE;
                }
            });
        }
        recordedIndexMetaData.clear();
        recordedMetaData = null;
    }

    @Override
    public void onCreateTable(String keyspace, String table) {
        recordedIndexMetaData.clear();
        recordedMetaData = null;
        KeyspaceMetadata ksm = Schema.instance.getKeyspaceMetadata(keyspace);
        TableMetadata cfm = Schema.instance.getTableMetadata(keyspace, table);
        if (ksm == null || cfm == null)
            return;
        logger.trace("{}.{}", ksm.name, cfm.name);
        if (!isElasticAdmin(ksm.name, cfm.name)) {
            updateElasticsearchMapping(ksm, cfm);
        }
        flushTransaction();
    }

    @Override
    public void onAlterTable(String keyspace, String table, boolean affectsStatements) {
        recordedIndexMetaData.clear();
        recordedMetaData = null;
        KeyspaceMetadata ksm = Schema.instance.getKeyspaceMetadata(keyspace);
        TableMetadata cfm = Schema.instance.getTableMetadata(keyspace, table);
        if (ksm == null || cfm == null)
            return;
        logger.trace("{}.{}", ksm.name, cfm.name);
        if (isElasticAdmin(ksm.name, cfm.name)) {
            recordedMetaData = clusterService.readMetaData(cfm);
        } else {
            updateElasticsearchMapping(ksm, cfm);
        }
        flushTransaction();
    }

    @Override
    public void onAlterKeyspace(String ksName) {
        logger.trace("{}", ksName);
        MetaData metadata = this.clusterService.state().metaData();
        InetAddressAndPort local = FBUtilities.getBroadcastAddressAndPort();
        for(ObjectCursor<IndexMetaData> imdCursor : metadata.indices().values()) {
            if (ksName.equals(imdCursor.value.keyspace())) {
                KeyspaceMetadata ksm = Schema.instance.getKeyspaceMetadata(ksName);
                if (ksm != null && ksm.params != null && ksm.params.replication != null && ksm.params.replication.klass.isAssignableFrom(NetworkTopologyStrategy.class)) {
                    String localDc = DatabaseDescriptor.getEndpointSnitch().getDatacenter(local);
                    try {
                        Integer rf = Integer.parseInt(ksm.params.replication.asMap().get(localDc));
                        if (!rf.equals(imdCursor.value.getNumberOfReplicas()+1)) {
                            logger.debug("Submit numberOfReplicas update  for indices based on keyspace [{}]", ksName);
                            clusterService.submitNumberOfShardsAndReplicasUpdate("update-shard-replicas", ksName);
                        }
                    } catch(NumberFormatException e) {
                        // ignore
                    }
                }
            }
        }
    }

    @Override
    public void onDropKeyspace(String ksName) {
        logger.trace("{}", ksName);
    }

    boolean isElasticAdmin(String ksName, String cfName) {
        return (clusterService.getElasticAdminKeyspaceName().equals(ksName) &&
                ClusterService.ELASTIC_ADMIN_METADATA_TABLE.equals(cfName));
    }

    void updateElasticsearchMapping(KeyspaceMetadata ksm, TableMetadata cfm) {
        boolean hasSecondaryIndex = cfm.indexes.has(SchemaManager.buildIndexName(cfm.name));
        for(Map.Entry<String, ByteBuffer> e : cfm.params.extensions.entrySet()) {
            if (clusterService.isValidExtensionKey(e.getKey())) {
                    IndexMetaData indexMetaData = clusterService.getIndexMetaDataFromExtension(e.getValue());
                    recordedIndexMetaData.put(indexMetaData.getIndex().getName(), indexMetaData);

                    if (hasSecondaryIndex)
                        indexMetaData.getMappings().forEach( m -> SchemaManager.typeToCfName(ksm.name, m.value.type()) );
            }
        }
    }

    @Override
    public void clusterChanged(ClusterChangedEvent event) {
        for(ElasticSecondaryIndex esi : ElasticSecondaryIndex.elasticSecondayIndices.values())
            esi.clusterChanged(event);
    }
}
