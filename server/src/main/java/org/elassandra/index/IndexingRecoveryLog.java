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

import org.apache.cassandra.db.ColumnFamilyStore;
import org.apache.cassandra.db.DecoratedKey;
import org.apache.cassandra.service.ElassandraDaemon;
import org.apache.cassandra.utils.ByteBufferUtil;
import org.apache.cassandra.utils.Hex;
import org.apache.logging.log4j.LogManager;
import org.apache.logging.log4j.Logger;

import java.io.IOException;
import java.nio.ByteBuffer;
import java.nio.ByteOrder;
import java.nio.channels.FileChannel;
import java.nio.file.DirectoryStream;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.Paths;
import java.nio.file.StandardOpenOption;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.atomic.AtomicLong;

/**
 * Durable per-partition record that search indexing still owes Cassandra. A key is fsynced before
 * the Lucene attempt and removed only after a Lucene flush that started after the note.
 */
final class IndexingRecoveryLog {
    private static final Logger logger = LogManager.getLogger(IndexingRecoveryLog.class);

    private final ColumnFamilyStore baseCfs;
    private final Path directory;
    private final ConcurrentHashMap<String, ByteBuffer> pendingKeys = new ConcurrentHashMap<>();
    private final ConcurrentHashMap<String, Long> pendingSeq = new ConcurrentHashMap<>();
    private final Set<String> indexedSinceNote = ConcurrentHashMap.newKeySet();
    private final AtomicLong seq = new AtomicLong();

    IndexingRecoveryLog(ColumnFamilyStore baseCfs) {
        this.baseCfs = baseCfs;
        this.directory = recoveryDirectory(baseCfs);
        try {
            Files.createDirectories(directory);
            try (DirectoryStream<Path> stream = Files.newDirectoryStream(directory)) {
                for (Path file : stream) {
                    if (Files.isDirectory(file)) {
                        continue;
                    }
                    String name = file.getFileName().toString();
                    try {
                        ByteBuffer key = ByteBuffer.wrap(Hex.hexToBytes(name));
                        pendingKeys.put(name, key);
                        pendingSeq.put(name, seq.incrementAndGet());
                    } catch (Exception e) {
                        logger.warn("ignoring unreadable recovery record {}", file, e);
                    }
                }
            }
        } catch (IOException e) {
            logger.error("failed to initialize indexing recovery log at {}", directory, e);
        }
    }

    private static Path recoveryDirectory(ColumnFamilyStore baseCfs) {
        try {
            return Paths.get(
                ElassandraDaemon.getElasticsearchDataDir(),
                "indexing-recovery",
                baseCfs.keyspace.getName(),
                baseCfs.name
            );
        } catch (Exception e) {
            return baseCfs.getDirectories().getDirectoryForNewSSTables().toPath().resolve("indexing-recovery");
        }
    }

    private static String keyId(ByteBuffer key) {
        return ByteBufferUtil.bytesToHex(key.duplicate());
    }

    void note(DecoratedKey key) {
        ByteBuffer copy = ByteBufferUtil.clone(key.getKey());
        String id = keyId(copy);
        long next = seq.incrementAndGet();
        pendingKeys.put(id, copy);
        pendingSeq.put(id, next);
        indexedSinceNote.remove(id);
        Path file = directory.resolve(id);
        ByteBuffer payload = ByteBuffer.allocate(8).order(ByteOrder.BIG_ENDIAN).putLong(next);
        payload.flip();
        try {
            Files.createDirectories(directory);
            try (FileChannel channel = FileChannel.open(file, StandardOpenOption.CREATE, StandardOpenOption.WRITE, StandardOpenOption.TRUNCATE_EXISTING)) {
                channel.write(payload);
                channel.force(true);
            }
        } catch (IOException e) {
            logger.error("failed to fsync indexing recovery record for {}", key, e);
        }
    }

    void indexed(DecoratedKey key) {
        indexedSinceNote.add(keyId(key.getKey()));
    }

    Map<String, Long> snapshot() {
        return new HashMap<>(pendingSeq);
    }

    void ack(Map<String, Long> snapshot) {
        if (snapshot == null || snapshot.isEmpty()) {
            return;
        }
        for (Map.Entry<String, Long> entry : snapshot.entrySet()) {
            if (!indexedSinceNote.contains(entry.getKey())) {
                continue;
            }
            if (pendingSeq.remove(entry.getKey(), entry.getValue())) {
                indexedSinceNote.remove(entry.getKey());
                pendingKeys.remove(entry.getKey());
                try {
                    Files.deleteIfExists(directory.resolve(entry.getKey()));
                } catch (IOException e) {
                    logger.warn("failed to remove indexing recovery record {}", entry.getKey(), e);
                }
            }
        }
    }

    boolean contains(ByteBuffer key) {
        return pendingSeq.containsKey(keyId(key));
    }

    int size() {
        return pendingSeq.size();
    }

    List<DecoratedKey> keys() {
        List<DecoratedKey> keys = new ArrayList<>(pendingKeys.size());
        for (ByteBuffer key : pendingKeys.values()) {
            keys.add(baseCfs.decorateKey(key.duplicate()));
        }
        return keys;
    }
}
