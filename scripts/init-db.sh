#!/bin/bash
# Initializes database with timezone info and root password, plus optional extra db/user

useradd mysql || true

# Install db
/usr/local/mysql/scripts/mariadb-install-db \
  --basedir=/usr/local/mysql \
  --datadir=/usr/local/mysql/data \
  --user=mysql --no-defaults

# Load timezone info into database
/usr/local/mysql/bin/mariadb-tzinfo-to-sql /usr/share/zoneinfo 1>/dev/null
if [ -n "$TZ" ]; then
  cp "/usr/share/zoneinfo/$TZ" /etc/localtime
  echo "$TZ" >/etc/timezone
else
  default_tz="America/Los_Angeles"
  cp "/usr/share/zoneinfo/$default_tz" /etc/localtime
  echo "$default_tz" >/etc/timezone
fi

ln -s /usr/local/mysql/support-files/systemd/* /usr/lib/systemd/system/

/usr/local/mysql/bin/mariadbd --user mysql &
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
  /tmp/scripts/secure-install-db.exp
fi

kill -SIGTERM "$(cat /usr/local/mysql/data/mariadb.pid)" || true
rm -rf /usr/local/mysql/data/mariadb.pid
sleep 10
