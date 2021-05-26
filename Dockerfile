ARG MARIADB_VER="10.5.10"
ARG ALPINE_VER="3.13"
ARG RUN_USER="mysql"
ARG PUID=40
ARG PGID=40

FROM alpine:${ALPINE_VER} AS sourcer
ARG MARIADB_VER
WORKDIR /tmp
RUN \
  #wget https://github.com/MariaDB/server/archive/refs/tags/mariadb-${MARIADB_VER}.tar.gz \
  wget https://downloads.mariadb.org/interstitial/mariadb-${MARIADB_VER}/source/mariadb-${MARIADB_VER}.tar.gz \
  -O /tmp/mdb.tar.gz \
  && tar -xf /tmp/mdb.tar.gz -C /tmp/ \
  && mv /tmp/mariadb-${MARIADB_VER} /tmp/server \
  && rm -rf /tmp/mdb.tar.gz

FROM alpine:${ALPINE_VER} AS common
RUN \
  apk update \
  && apk add --no-cache \
  # general libs
  gnutls-dev openssl libevent-dev libaio-dev \
  # compression
  lz4-dev zstd-dev zlib-dev xz-libs \
  # rocksdb
  readline \
  # connect odbc
  unixodbc \
  # connect xpath
  libxml2-dev \
  # connect jpath and mongo
  libbson-dev mongo-c-driver-dev \
  # clib
  gcc g++

FROM common AS builder
RUN \
  apk add --no-cache \
  git gnupg \
  build-base samurai cmake extra-cmake-modules ccache \
  ncurses-dev bison curl-dev linux-headers \
  boost-dev flex linux-pam-dev

FROM builder AS packager
COPY --from=sourcer /tmp/server /tmp/server
RUN \
  mkdir /tmp/build \
  && cmake -S /tmp/server -B /tmp/build \
  -Werror=dev \
  -DCONC_WITH_{UNITTEST,SSL}=OFF \
  -DWITH_EMBEDDED_SERVER=OFF \
  -DWITH_UNIT_TESTS=OFF \
  -DCMAKE_BUILD_TYPE=Release \
  -DPLUGIN_{ARCHIVE,TOKUDB,MROONGA,OQGRAPH,SPIDER,SPHINX}=NO \
  -DCONNECT_WITH_MONGO=ON \
  -DWITH_SSL=bundled \
  -DMYSQL_MAINTAINER_MODE=OFF \
  -DWITH_SAFEMALLOC=OFF \
  -G Ninja \
  && cmake --build /tmp/build/ --parallel 12 -t package \
  && rm -rf /tmp/server \
  && apk del \
  git gnupg \
  build-base \
  samurai cmake extra-cmake-modules ccache \
  ncurses-dev bison curl-dev linux-headers \
  boost-dev flex libbson-dev linux-pam-dev

FROM common AS runtime
ARG MARIADB_VER
ARG RUN_USER
ARG PUID
ARG PGID
COPY --from=packager /tmp/build/mariadb-${MARIADB_VER}-linux-x86_64.tar.gz /tmp/build/mariadb-${MARIADB_VER}-linux-x86_64.tar.gz
RUN \
  cd /tmp && tar -zpxf ./build/mariadb-${MARIADB_VER}-linux-x86_64.tar.gz \
  && rm -f mariadb-${MARIADB_VER}-linux-x86_64.tar.gz \
  && rm -rf /tmp/build /tmp/mariadb-${MARIADB_VER}-linux-x86_64/mysql-test \
  && addgroup -S -g ${PGID} ${RUN_USER} \
  && adduser -S -D -H -u ${PUID} -G ${RUN_USER} -g "MySQL" ${RUN_USER} \
  && apk add --no-cache tzdata bash logrotate \
  && mkdir -p /usr/local/mysql \
  && cp -a /tmp/mariadb-${MARIADB_VER}-linux-x86_64/* /usr/local/mysql \
  && chown -R ${RUN_USER} /usr/local/mysql/ || true \
  && rm -rf /tmp/mariadb-${MARIADB_VER}-linux-x86_64 \
  && mkdir -p /etc/mysql/conf.d \
  && chown -R ${RUN_USER} /etc/mysql/conf.d/

COPY ./scripts /tmp/scripts
COPY ./my.cnf /etc/mysql/my.cnf
COPY ./logrotate /etc/logrotate.d/mariadb_slow_log

ENV PATH="/usr/local/mysql/bin:$PATH"

ENTRYPOINT [ "/tmp/scripts/init.sh" ]
SHELL [ "bash" ]

VOLUME [ "/usr/local/mysql/data" ]
VOLUME [ "/etc/mysql/conf.d" ]

EXPOSE 3306
