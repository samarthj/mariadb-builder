#!/bin/bash

if [ ! -d "/usr/local/mysql/data/mysql" ]; then
  /tmp/scripts/init-db.sh
fi
/tmp/scripts/run-db.sh
