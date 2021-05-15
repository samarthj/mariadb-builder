#!/bin/bash
# Initializes database with timezone info and root password, plus optional extra db/user

if [ -d "/usr/local/mysql/data/mysql" ]; then
  exit 0
fi

# setting ulimits
mysql soft nofile 65535
mysql hard nofile 65535
mysql soft core unlimited
mysql hard core unlimited

# Install db
/usr/local/mysql/scripts/mariadb-install-db \
--basedir=/usr/local/mysql \
--datadir=/usr/local/mysql/data \
--user=mysql --no-defaults

# Load timezone info into database
apk add tzdata
/usr/local/mysql/bin/mariadb-tzinfo-to-sql /usr/share/zoneinfo 1>/dev/null
if [ -n "$TZ" ]; then
  cp "/usr/share/zoneinfo/$TZ" /etc/localtime
  echo "$TZ" >  /etc/timezone
else
  default_tz="America/Los_Angeles"
  cp "/usr/share/zoneinfo/$default_tz" /etc/localtime
  echo "$default_tz" >  /etc/timezone
fi
apk del tzdata

/tmp/scripts/run-db.sh &
sleep 30
# Setup user
if [ -n "$MARIADB_USER" ] && [ -n "$MARIADB_PASSWORD" ]; then
  echo "Creating user '${MARIADB_USER}'"
  mysql -uroot -e "CREATE USER '${MARIADB_USER}' IDENTIFIED BY '${MARIADB_PASSWORD}' ;"

  if [ -n "$MARIADB_DATABASE" ]; then
    echo "Giving user '${MARIADB_USER}' access to schema \`${MARIADB_DATABASE}\`"
    mysql -uroot -e "GRANT ALL ON \`${MARIADB_DATABASE}\`.* TO '${MARIADB_USER}' ;"
  else
    echo "Giving user '${MARIADB_USER}' access to everything"
    mysql -uroot -e "GRANT ALL ON *.* TO '${MARIADB_USER}' ;"
  fi
fi

# Secure installation
if [ -n "$MARIADB_ROOT_PASSWORD" ]; then
  apk add expect
  /tmp/scripts/secure-install-db.exp
  apk del expect
fi

kill -SIGTERM "$(cat /usr/local/mysql/data/mariadb.pid)" || true
rm -rf /usr/local/mysql/data/mariadb.pid
sleep 10
