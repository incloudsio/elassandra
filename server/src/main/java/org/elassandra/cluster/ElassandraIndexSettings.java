/*
 * Elassandra-only index {@link org.elasticsearch.common.settings.Setting}s (fork parity with
 * {@link org.elasticsearch.cluster.metadata.IndexMetaData}). Stock OpenSearch {@code IndexMetadata}
 * does not declare these; side-car code uses this class after package rewrites.
 */
package org.elassandra.cluster;

import org.elasticsearch.cluster.service.ClusterService;
import org.elasticsearch.common.settings.Setting;
import org.elasticsearch.common.settings.Setting.Property;

/**
 * Boolean index settings referenced by {@code ElasticSecondaryIndex.ImmutableMappingInfo}.
 */
public final class ElassandraIndexSettings {

    public static final String INDEX_SETTING_PREFIX = "index.";

    public static final Setting<Boolean> INDEX_SYNCHRONOUS_REFRESH_SETTING = Setting.boolSetting(
        INDEX_SETTING_PREFIX + ClusterService.SYNCHRONOUS_REFRESH,
        Boolean.getBoolean(ClusterService.SETTING_SYSTEM_SYNCHRONOUS_REFRESH),
        Property.Dynamic,
        Property.IndexScope
    );

    public static final Setting<Boolean> INDEX_SNAPSHOT_WITH_SSTABLE_SETTING = Setting.boolSetting(
        INDEX_SETTING_PREFIX + ClusterService.SNAPSHOT_WITH_SSTABLE,
        Boolean.getBoolean(ClusterService.SETTING_SYSTEM_SNAPSHOT_WITH_SSTABLE),
        Property.Dynamic,
        Property.IndexScope
    );

    public static final Setting<Boolean> INDEX_INCLUDE_HOST_ID_SETTING = Setting.boolSetting(
        INDEX_SETTING_PREFIX + ClusterService.INCLUDE_HOST_ID,
        false,
        Property.Final,
        Property.IndexScope
    );

    public static final Setting<Boolean> INDEX_INDEX_ON_COMPACTION_SETTING = Setting.boolSetting(
        INDEX_SETTING_PREFIX + ClusterService.INDEX_ON_COMPACTION,
        Boolean.getBoolean(ClusterService.SETTING_SYSTEM_INDEX_ON_COMPACTION),
        Property.Dynamic,
        Property.IndexScope
    );

    public static final Setting<Boolean> INDEX_INDEX_STATIC_COLUMNS_SETTING = Setting.boolSetting(
        INDEX_SETTING_PREFIX + ClusterService.INDEX_STATIC_COLUMNS,
        false,
        Property.Dynamic,
        Property.IndexScope
    );

    public static final Setting<Boolean> INDEX_INDEX_STATIC_ONLY_SETTING = Setting.boolSetting(
        INDEX_SETTING_PREFIX + ClusterService.INDEX_STATIC_ONLY,
        false,
        Property.Dynamic,
        Property.IndexScope
    );

    public static final Setting<Boolean> INDEX_INDEX_STATIC_DOCUMENT_SETTING = Setting.boolSetting(
        INDEX_SETTING_PREFIX + ClusterService.INDEX_STATIC_DOCUMENT,
        false,
        Property.Dynamic,
        Property.IndexScope
    );

    public static final Setting<Boolean> INDEX_INDEX_INSERT_ONLY_SETTING = Setting.boolSetting(
        INDEX_SETTING_PREFIX + ClusterService.INDEX_INSERT_ONLY,
        Boolean.getBoolean(ClusterService.SETTING_SYSTEM_INDEX_INSERT_ONLY),
        Property.Dynamic,
        Property.IndexScope
    );

    public static final Setting<Boolean> INDEX_INDEX_OPAQUE_STORAGE_SETTING = Setting.boolSetting(
        INDEX_SETTING_PREFIX + ClusterService.INDEX_OPAQUE_STORAGE,
        Boolean.getBoolean(ClusterService.SETTING_SYSTEM_INDEX_OPAQUE_STORAGE),
        Property.Final,
        Property.IndexScope
    );

    private ElassandraIndexSettings() {}
}
