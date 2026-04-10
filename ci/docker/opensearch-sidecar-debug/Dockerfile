# JDK 11 image for OpenSearch 1.3 side-car compile/test in Linux (local debug).
FROM eclipse-temurin:11-jdk

RUN apt-get update && apt-get install -y --no-install-recommends \
    git \
    rsync \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

ENV JAVA_HOME=/opt/java/openjdk
WORKDIR /workspace/elassandra
