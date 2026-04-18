################################################################################
# This Dockerfile was generated from the template at distribution/src/docker/Dockerfile
#
# Beginning of multi stage Dockerfile
################################################################################
<% /*
  This file is passed through Groovy's SimpleTemplateEngine, so dollars and backslashes
  have to be escaped in order for them to appear in the final Dockerfile. You
  can also comment out blocks, like this one. See:

  https://docs.groovy-lang.org/latest/html/api/groovy/text/SimpleTemplateEngine.html

  We use control-flow tags in this file to conditionally render the content. The
  layout/presentation here has been adjusted so that it looks reasonable when rendered,
  at the slight expense of how it looks here.
*/ %>
################################################################################
# Build stage 0 `builder`:
# Extract the merged Elassandra distribution and overlay Cassandra tooling.
################################################################################

FROM ${base_image} AS builder

RUN set -eux ; \\
    tini_bin="" ; \\
    case "\$(arch)" in \\
        aarch64) tini_bin='tini-arm64' ;; \\
        x86_64)  tini_bin='tini-amd64' ;; \\
        *) echo >&2 ; echo >&2 "Unsupported architecture \$(arch)" ; echo >&2 ; exit 1 ;; \\
    esac ; \\
    curl --retry 8 -S -L -O https://github.com/krallin/tini/releases/download/v0.19.0/\${tini_bin} ; \\
    curl --retry 8 -S -L -O https://github.com/krallin/tini/releases/download/v0.19.0/\${tini_bin}.sha256sum ; \\
    sha256sum -c \${tini_bin}.sha256sum ; \\
    rm \${tini_bin}.sha256sum ; \\
    mv \${tini_bin} /tini ; \\
    chmod +x /tini

RUN mkdir -p /usr/share/elassandra
WORKDIR /usr/share/elassandra

${source_distribution}

RUN tar zxf /opt/elassandra.tar.gz --strip-components=1
RUN mkdir -p conf data logs pylib
COPY cassandra/bin bin/
COPY cassandra/conf conf/
COPY cassandra/pylib pylib/
COPY config/opensearch.yml conf/
COPY bin/docker-entrypoint.sh bin/configure-elassandra.py /tmp/
RUN chmod +x bin/* /tmp/docker-entrypoint.sh /tmp/configure-elassandra.py && \\
    sed -i 's/classname="org.apache.cassandra.service.CassandraDaemon"/classname="org.apache.cassandra.service.ElassandraDaemon"/' /usr/share/elassandra/bin/cassandra && \\
    rm -rf /usr/share/elassandra/modules/ingest-user-agent && \\
    rm -f /usr/share/elassandra/lib/guava-*.jar && \\
    rm -f /usr/share/elassandra/lib/failureaccess-*.jar && \\
    rm -f /usr/share/elassandra/lib/snakeyaml-*.jar && \\
    curl --retry 8 -S -L --output /usr/share/elassandra/lib/guava-27.0-jre.jar \\
      https://repo.maven.apache.org/maven2/com/google/guava/guava/27.0-jre/guava-27.0-jre.jar && \\
    curl --retry 8 -S -L --output /usr/share/elassandra/lib/snakeyaml-1.26.jar \\
      https://repo.maven.apache.org/maven2/org/yaml/snakeyaml/1.26/snakeyaml-1.26.jar && \\
    curl --retry 8 -S -L --output /usr/share/elassandra/lib/snappy-java-1.1.10.4.jar \\
      https://repo.maven.apache.org/maven2/org/xerial/snappy/snappy-java/1.1.10.4/snappy-java-1.1.10.4.jar && \\
    curl --retry 8 -S -L --output /usr/share/elassandra/lib/commons-math3-3.2.jar \\
      https://repo.maven.apache.org/maven2/org/apache/commons/commons-math3/3.2/commons-math3-3.2.jar && \\
    curl --retry 8 -S -L --output /usr/share/elassandra/lib/metrics-jvm-3.1.5.jar \\
      https://repo.maven.apache.org/maven2/io/dropwizard/metrics/metrics-jvm/3.1.5/metrics-jvm-3.1.5.jar && \\
    curl --retry 8 -S -L --output /usr/share/elassandra/lib/logback-core-1.2.9.jar \\
      https://repo.maven.apache.org/maven2/ch/qos/logback/logback-core/1.2.9/logback-core-1.2.9.jar && \\
    curl --retry 8 -S -L --output /usr/share/elassandra/lib/logback-classic-1.2.9.jar \\
      https://repo.maven.apache.org/maven2/ch/qos/logback/logback-classic/1.2.9/logback-classic-1.2.9.jar

################################################################################
# Build stage 1 (the actual Elassandra image).
################################################################################

FROM ${base_image}

ENV ELASSANDRA_HOME=/usr/share/elassandra \\
    CASSANDRA_HOME=/usr/share/elassandra \\
    CASSANDRA_CONF=/usr/share/elassandra/conf \\
    JAVA_HOME=/usr/share/elassandra/jdk \\
    OPENSEARCH_CONTAINER=true

RUN  sed -i 's/mirrorlist/#mirrorlist/g' /etc/yum.repos.d/CentOS-Linux-* && \\
     sed -i 's|#baseurl=http://mirror.centos.org|baseurl=http://vault.epel.cloud|g' /etc/yum.repos.d/CentOS-Linux-* && \\
     for iter in {1..10}; do \\
      ${package_manager} update --setopt=tsflags=nodocs -y && \\
      ${package_manager} install --setopt=tsflags=nodocs -y \\
        nc shadow-utils zip unzip python3 which hostname procps-ng && \\
      ${package_manager} clean all && exit_code=0 && break || exit_code=\$? && echo "${package_manager} error: retry \$iter in 10s" && \\
      sleep 10; \\
    done; \\
    (exit \$exit_code)

RUN groupadd -g 1000 elassandra && \\
    adduser -u 1000 -g 1000 -G 0 -d /usr/share/elassandra elassandra && \\
    chmod 0775 /usr/share/elassandra

WORKDIR /usr/share/elassandra
COPY --from=builder --chown=1000:0 /usr/share/elassandra /usr/share/elassandra
COPY --from=builder --chown=0:0 /tini /tini
COPY --from=builder --chown=0:0 /tmp/docker-entrypoint.sh /usr/local/bin/docker-entrypoint.sh
COPY --from=builder --chown=0:0 /tmp/configure-elassandra.py /usr/local/bin/configure-elassandra.py

RUN ln -sf /etc/pki/ca-trust/extracted/java/cacerts /usr/share/elassandra/jdk/lib/security/cacerts

ENV PATH /usr/share/elassandra/jdk/bin:/usr/share/elassandra/bin:\$PATH

RUN find /usr/share/elassandra/jdk -type d -exec chmod 0755 '{}' \\; && \\
    chmod g=u /etc/passwd && \\
    chmod 0775 /usr/local/bin/docker-entrypoint.sh /usr/local/bin/configure-elassandra.py && \\
    chown -R 1000:0 /usr/share/elassandra

RUN find / -xdev -perm -4000 -exec chmod ug-s {} +

EXPOSE 7000 7001 7199 9042 9160 9200 9300

LABEL org.label-schema.build-date="${build_date}" \\
  org.label-schema.license="${license}" \\
  org.label-schema.name="Elassandra" \\
  org.label-schema.schema-version="1.0" \\
  org.label-schema.url="https://elassandra.org" \\
  org.label-schema.usage="https://github.com/incloudsio/elassandra" \\
  org.label-schema.vcs-ref="${git_revision}" \\
  org.label-schema.vcs-url="https://github.com/incloudsio/elassandra" \\
  org.label-schema.vendor="inClouds" \\
  org.label-schema.version="${version}" \\
  org.opencontainers.image.created="${build_date}" \\
  org.opencontainers.image.documentation="https://elassandra.org" \\
  org.opencontainers.image.licenses="${license}" \\
  org.opencontainers.image.revision="${git_revision}" \\
  org.opencontainers.image.source="https://github.com/incloudsio/elassandra" \\
  org.opencontainers.image.title="Elassandra" \\
  org.opencontainers.image.url="https://elassandra.org" \\
  org.opencontainers.image.vendor="inClouds" \\
  org.opencontainers.image.version="${version}"

ENTRYPOINT ["/tini", "--", "/usr/local/bin/docker-entrypoint.sh"]
CMD ["elassandra"]

################################################################################
# End of multi-stage Dockerfile
################################################################################
