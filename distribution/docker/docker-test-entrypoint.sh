#!/bin/bash
cd /usr/share/elassandra/bin/

/usr/local/bin/docker-entrypoint.sh | tee > /usr/share/elassandra/logs/console.log
