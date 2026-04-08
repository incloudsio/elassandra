/*
 * Licensed to Elasticsearch under one or more contributor
 * license agreements. See the NOTICE file distributed with
 * this work for additional information regarding copyright
 * ownership. Elasticsearch licenses this file to you under the Apache License,
 * Version 2.0 (the "License"); you may not use this file except in compliance
 * with the License. You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

package org.elassandra.search.aggregations.bucket.token;

import org.elasticsearch.common.io.stream.StreamInput;
import org.elasticsearch.common.xcontent.ObjectParser;
import org.elasticsearch.common.xcontent.XContentParser;
import org.elasticsearch.search.DocValueFormat;
import org.elasticsearch.search.aggregations.AggregationBuilder;
import org.elasticsearch.search.aggregations.AggregatorFactories.Builder;
import org.elasticsearch.search.aggregations.AggregatorFactory;
import org.elasticsearch.search.aggregations.bucket.range.RangeAggregationBuilder;
import org.elasticsearch.search.aggregations.bucket.range.RangeAggregator;
import org.elasticsearch.search.aggregations.bucket.range.RangeAggregator.Range;
import org.elasticsearch.search.aggregations.bucket.range.RangeAggregatorFactory;
import org.elasticsearch.search.aggregations.bucket.range.TokenRangeAggregatorFactory;
import org.elasticsearch.search.aggregations.support.ValuesSource.Numeric;
import org.elasticsearch.search.aggregations.support.ValuesSourceConfig;
import org.elasticsearch.search.aggregations.support.ValuesSourceParserHelper;
import org.elasticsearch.search.internal.SearchContext;

import java.io.IOException;
import java.util.Map;

/**
 * Token (Cassandra partition token) histogram / range aggregation. Implemented as a thin wrapper over
 * the numeric {@link RangeAggregationBuilder} with a distinct aggregation type for Elassandra routing.
 */
public class TokenRangeAggregationBuilder extends RangeAggregationBuilder {

    public static final String NAME = "token_range";

    private static final ObjectParser<TokenRangeAggregationBuilder, Void> PARSER;
    static {
        PARSER = new ObjectParser<>(NAME);
        ValuesSourceParserHelper.declareNumericFields(PARSER, true, true, false);
        PARSER.declareBoolean(TokenRangeAggregationBuilder::keyed, RangeAggregator.KEYED_FIELD);

        PARSER.declareObjectArray((agg, ranges) -> {
            for (Range range : ranges) {
                agg.addRange(range);
            }
        }, (p, c) -> Range.fromXContent(p), RangeAggregator.RANGES_FIELD);
    }

    public static AggregationBuilder parse(String aggregationName, XContentParser context) throws IOException {
        return PARSER.parse(context, new TokenRangeAggregationBuilder(aggregationName), null);
    }

    public TokenRangeAggregationBuilder(String name) {
        super(name);
    }

    public TokenRangeAggregationBuilder(StreamInput in) throws IOException {
        super(in);
    }

    protected TokenRangeAggregationBuilder(TokenRangeAggregationBuilder clone, Builder factoriesBuilder, Map<String, Object> metaData) {
        super(clone, factoriesBuilder, metaData);
    }

    @Override
    protected AggregationBuilder shallowCopy(Builder factoriesBuilder, Map<String, Object> metaData) {
        return new TokenRangeAggregationBuilder(this, factoriesBuilder, metaData);
    }

    public TokenRangeAggregationBuilder addRange(String key, long from, long to) {
        addRange(new Range(key, (double) from, (double) to));
        return this;
    }

    public TokenRangeAggregationBuilder addRange(long from, long to) {
        return addRange(null, from, to);
    }

    public TokenRangeAggregationBuilder addUnboundedTo(String key, long to) {
        addRange(new Range(key, null, (double) to));
        return this;
    }

    public TokenRangeAggregationBuilder addUnboundedTo(long to) {
        return addUnboundedTo(null, to);
    }

    public TokenRangeAggregationBuilder addUnboundedFrom(String key, long from) {
        addRange(new Range(key, (double) from, null));
        return this;
    }

    public TokenRangeAggregationBuilder addUnboundedFrom(long from) {
        return addUnboundedFrom(null, from);
    }

    @Override
    protected RangeAggregatorFactory innerBuild(SearchContext context, ValuesSourceConfig<Numeric> config,
            AggregatorFactory<?> parent, Builder subFactoriesBuilder) throws IOException {
        Range[] ranges = processRanges(range -> {
            DocValueFormat parser = config.format();
            assert parser != null;
            Double from = range.getFrom();
            Double to = range.getTo();
            if (range.getFromAsString() != null) {
                from = parser.parseDouble(range.getFromAsString(), false, context.getQueryShardContext()::nowInMillis);
            }
            if (range.getToAsString() != null) {
                to = parser.parseDouble(range.getToAsString(), false, context.getQueryShardContext()::nowInMillis);
            }
            return new Range(range.getKey(), from, range.getFromAsString(), to, range.getToAsString());
        });
        if (ranges.length == 0) {
            throw new IllegalArgumentException("No [ranges] specified for the [" + this.getName() + "] aggregation");
        }
        return new TokenRangeAggregatorFactory(name, config, ranges, keyed, rangeFactory, context, parent,
                subFactoriesBuilder, metaData);
    }

    @Override
    public String getType() {
        return NAME;
    }
}
