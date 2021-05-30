# syntax=docker/dockerfile

ARG MARIADB_VER="10.6"
ARG OS_VER="sid-slim"
ARG RUN_USER="mysql"
ARG PUID=40
ARG PGID=40
ARG CORES=4
ARG TZ="America/Los_Angeles"

FROM docker.io/debian:${OS_VER} AS common
WORKDIR /tmp
ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update \
  && apt-get install -y --no-install-recommends \
  git gnupg ca-certificates

FROM common AS source
ARG MARIADB_VER
ARG CORES
RUN git clone --depth=1 --recurse-submodules --shallow-submodules -j ${CORES} \
  --branch bb-${MARIADB_VER}-release "https://github.com/MariaDB/server.git"

FROM common AS mariadb-build-dep
ARG MARIADB_VER
RUN apt-key adv --recv-keys \
  --keyserver hkp://keyserver.ubuntu.com:80 \
  0xF1656F24C74CD1D8 \
  && mkdir -p /etc/apt/sources.list.d \
  && echo "deb [arch=amd64] \
  http://sfo1.mirrors.digitalocean.com/mariadb/repo/${MARIADB_VER}/$(sed -n -e 's/^ID=//p' /etc/os-release) \
  sid main" > /etc/apt/sources.list.d/MariaDB.list \
  && echo "deb-src [arch=amd64] \
  http://sfo1.mirrors.digitalocean.com/mariadb/repo/${MARIADB_VER}/$(sed -n -e 's/^ID=//p' /etc/os-release) \
  sid main" >> /etc/apt/sources.list.d/MariaDB.list \
  && apt-get update \
  && apt-get build-dep -y mariadb-server

FROM mariadb-build-dep AS build-dep
RUN mkdir /tmp/build \
  && apt-get install -y --no-install-recommends \
  build-essential gcc g++ libncurses5-dev gnutls-dev bison zlib1g-dev ccache ninja-build \
  # llvm clang \
  libreadline-dev pkg-config \
  libgoogle-perftools-dev libjemalloc-dev \
  # libmongoc-dev \
  libevent-dev libzstd-dev \
  liburing-dev libaio-dev

FROM build-dep AS maker
COPY --from=source /tmp/server /tmp/server
ARG MARIADB_VER
ARG CORES
ADD CMakeExtra.txt /tmp/build/
RUN \
  cmake -S /tmp/server -B /tmp/build \
  -DCMAKE_USER_MAKE_RULES_OVERRIDE=/tmp/build/CMakeExtra.txt \
  -DCMAKE_EXE_LINKER_FLAGS='-ltcmalloc' \
  -DWITH_GPROF=ON \
  -DWITH_NUMA=ON \
  -DWITH_PMEM=ON \
  -DWITH_SAFEMALLOC=OFF \
  -DWITH_TSAN=ON \
  -DWITH_UBSAN=ON \
  # -DCMAKE_INCLUDE_DIRECTORIES_BEFORE=ON \
  # -DINSTALL_LAYOUT=DEB \
  # -Werror=dev \
  -DCONC_WITH_UNITTEST=OFF \
  -DWITH_UNIT_TESTS=OFF \
  -DWITH_EMBEDDED_SERVER=OFF \
  -DWITH_UNIT_TESTS=OFF \
  -DCMAKE_BUILD_TYPE=Release \
  -DPLUGIN_ARCHIVE=NO \
  -DPLUGIN_AUTH_ED25519=NO \
  -DPLUGIN_AUTH_GSSAPI=NO \
  # -DPLUGIN_AUTH_PAM=NO \
  -DPLUGIN_BLACKHOLE=NO \
  -DPLUGIN_CRACKLIB_PASSWORD_CHECK=NO \
  -DPLUGIN_DAEMON_EXAMPLE=NO \
  -DPLUGIN_DIALOG_EXAMPLES=NO \
  -DPLUGIN_EXAMPLE=NO \
  -DPLUGIN_EXAMPLE_KEY_MANAGEMENT=NO \
  -DPLUGIN_FEEDBACK=NO \
  -DPLUGIN_FTEXAMPLE=NO \
  -DPLUGIN_MROONGA=NO \
  -DPLUGIN_OQGRAPH=NO \
  -DPLUGIN_SEQUENCE=NO \
  -DPLUGIN_SPIDER=NO \
  -DPLUGIN_SPHINX=NO \
  # -DPLUGIN_WSREP_INFO=NO \
  -DCONNECT_WITH_MONGO=OFF \
  -DWITH_INNODB_LZ4=ON \
  -DWITH_ROCKSDB_JEMALLOC=ON \
  -DWITH_ROCKSDB_LZ4=ON \
  -DWITH_ROCKSDB_ZSTD=ON \
  -DWITH_ROCKSDB_snappy=OFF \
  -DPLUGIN_ROCKSDB=YES \
  -DMYSQL_MAINTAINER_MODE=NO \
  -DWITH_READLINE=ON \
  -DWITH_URING=ON \
  -G Ninja \
  -LAH && true \
  && cmake --build /tmp/build/ \
  --parallel ${CORES} -t package
RUN tar -zpxf /tmp/build/mariadb-${MARIADB_VER}*.tar.gz --exclude "mysql-test"

FROM docker.io/debian:${OS_VER} AS runtime
ARG MARIADB_VER
ARG RUN_USER
ARG PUID
ARG PGID
ARG TZ
RUN \
  apt-get update \
  && apt-get install -y --no-install-recommends \
  # general libs
  gnutls-bin tzdata logrotate expect systemd \
  libreadline8 libxml2 unixodbc \
  zlib1g liblz4-1 libzstd1 \
  libgoogle-perftools4 libjemalloc2 openssl \
  liburing1 libaio1 libpmem1 libnuma1
RUN groupadd ${RUN_USER} \
  && useradd -M -g ${RUN_USER} ${RUN_USER} \
  && mkdir /usr/local/mysql
COPY --chown=${RUN_USER}:${RUN_USER} --from=maker /tmp/mariadb-${MARIADB_VER}*-linux-x86_64 /usr/local/mysql
RUN mkdir -p /etc/mysql/conf.d
RUN mkdir -p /usr/local/mysql/data
RUN ln -s /usr/local/mysql/support-files/systemd/* /lib/systemd/system/

ADD scripts /tmp/scripts
ADD my.cnf /etc/mysql/my.cnf
ADD logrotate /etc/logrotate.d/mariadb_slow_log

ENV PATH="/bin:/usr/bin:/usr/local/mysql/bin:$PATH"

ENTRYPOINT [ "/tmp/scripts/init.sh" ]

VOLUME [ "/usr/local/mysql/data" ]
VOLUME [ "/etc/mysql/conf.d" ]

EXPOSE 3306

# FROM scratch AS exporter2
# COPY --from=maker /tmp/cmake-options.txt .
# COPY --from=packager /tmp/cmake-output.txt .
# COPY --from=packager /tmp/mdb.tar.gz .
