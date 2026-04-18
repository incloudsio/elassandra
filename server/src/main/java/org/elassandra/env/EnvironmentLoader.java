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

package org.elassandra.env;

import org.opensearch.common.settings.Settings;
import org.opensearch.env.Environment;

import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.Paths;

/**
 * Elasticsearch file configuration loader interface.
 */
public interface EnvironmentLoader {

    default Environment loadEnvironment(boolean foreground, String homeDir, String configDir) {
        final Path cfg = Paths.get(configDir);
        final Settings.Builder settings = Settings.builder()
            .put("node.name", "node0")
            .put("path.home", homeDir);

        // Docker only relies on a couple of flat OpenSearch settings. Parse those directly so
        // Elassandra can boot with Cassandra's SnakeYAML runtime instead of OpenSearch's YAML parser.
        loadFlatSettings(settings, cfg.resolve("opensearch.yml"));

        if (settings.get("cluster.name") == null) {
            settings.put("cluster.name", "elassandra");
        }

        if (settings.get("network.host") == null) {
            settings.put("network.host", "0.0.0.0");
        }

        String discoveryType = System.getenv("OPENSEARCH_DISCOVERY_TYPE");
        if (discoveryType != null && discoveryType.isEmpty() == false) {
            settings.put("discovery.type", discoveryType);
        }

        return new Environment(settings.build(), cfg);
    }

    static void loadFlatSettings(Settings.Builder settings, Path opensearchYml) {
        if (Files.isRegularFile(opensearchYml) == false) {
            return;
        }

        try {
            for (String rawLine : Files.readAllLines(opensearchYml)) {
                String line = rawLine.trim();
                if (line.isEmpty() || line.startsWith("#")) {
                    continue;
                }

                int separator = line.indexOf(':');
                if (separator <= 0) {
                    continue;
                }

                String key = line.substring(0, separator).trim();
                String value = line.substring(separator + 1).trim();
                int inlineComment = value.indexOf(" #");
                if (inlineComment >= 0) {
                    value = value.substring(0, inlineComment).trim();
                }
                if ((value.startsWith("\"") && value.endsWith("\"")) || (value.startsWith("'") && value.endsWith("'"))) {
                    value = value.substring(1, value.length() - 1);
                }
                if (value.isEmpty() == false) {
                    settings.put(key, value);
                }
            }
        } catch (IOException e) {
            throw new RuntimeException(e);
        }
    }

}
