ARG MARIADB_VER="10.5"
ARG OS_VER="sid-slim"
ARG RUN_USER="mysql"
ARG PUID=40
ARG PGID=40
ARG CORES=4
ARG TZ="America/Los_Angeles"

FROM docker.io/library/debian:${OS_VER} AS common
WORKDIR /tmp
ENV DEBIAN_FRONTEND=noninteractive
RUN \
  apt-get update \
  && apt-get install -y \
  git gnupg gcc g++

FROM common AS source
ARG MARIADB_VER
ARG CORES
RUN \
  git clone --depth=1 --recurse-submodules --shallow-submodules -j ${CORES} --branch ${MARIADB_VER} https://github.com/MariaDB/server.git

FROM common AS mariadb-build-dep
ARG MARIADB_VER
RUN apt-key adv --recv-keys \
  --keyserver hkp://keyserver.ubuntu.com:80 \
  0xF1656F24C74CD1D8 \
  && mkdir -p /etc/apt/sources.list.d \
  && echo "deb [arch=amd64] http://sfo1.mirrors.digitalocean.com/mariadb/repo/${MARIADB_VER}/debian sid main" > /etc/apt/sources.list.d/MariaDB.list  \
  && echo "deb-src [arch=amd64] http://sfo1.mirrors.digitalocean.com/mariadb/repo/${MARIADB_VER}/debian sid main" >> /etc/apt/sources.list.d/MariaDB.list \
  && apt-get update \
  && apt-get build-dep -y mariadb-server

FROM mariadb-build-dep AS build-dep
RUN \
  mkdir /tmp/build \
  && apt-get install -y \
  build-essential libncurses5-dev gnutls-dev bison zlib1g-dev ccache ninja-build \
  # llvm clang \
  libreadline-dev pkg-config \
  libgoogle-perftools-dev libjemalloc-dev \
  # libmongoc-dev \
  libevent-dev libzstd-dev \
  liburing-dev libaio-dev
# RUN mkdir -p /usr/share/man/man1
# RUN apt-get install -y --no-install-recommends openjdk-11-jdk-headless
# RUN git clone https://github.com/mongodb/mongo-c-driver.git \
#   && cd mongo-c-driver \
#   && python build/calc_release_version.py > VERSION_CURRENT
# RUN mkdir /tmp/mongoc-build
# RUN cmake -S /tmp/mongo-c-driver -B /tmp/mongoc-build \
#   -DENABLE_AUTOMATIC_INIT_AND_CLEANUP=OFF \
#   -DCMAKE_BUILD_TYPE=Release \
#   && cmake --build /tmp/mongoc-build/ -t install
COPY ./CMakeExtra.txt /tmp/build/

FROM build-dep AS maker
COPY --from=source /tmp/server /tmp/server
ARG MARIADB_VER
ARG CORES
RUN \
  # export CC=/usr/bin/clang \
  # && export CXX=/usr/bin/clang++ \
  cmake -S /tmp/server -B /tmp/build \
  -DCMAKE_USER_MAKE_RULES_OVERRIDE=/tmp/build/CMakeExtra.txt \
  -DCMAKE_EXE_LINKER_FLAGS='-ltcmalloc' \
  -DWITH_SAFEMALLOC=OFF \
  -DWITH_TSAN=ON \
  -DWITH_UBSAN=ON \
  # -DCMAKE_CXX_STANDARD_REQUIRED=17 \
  # -DMONGOC_INCLUDE_DIRS='/usr/include/libmongoc-1.0 /usr/include/libbson-1.0' \
  # -DBSON_INCLUDE_DIRS='/usr/include/libbson-1.0' \
  # -Dlibmongoc-1.0_DIR=/tmp/mongoc-build \
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
  -LAH 2>&1 | tee cmake-options.txt

FROM maker AS packager
ARG MARIADB_VER
ARG CORES
RUN \
  # export CC=/usr/bin/clang \
  # && export CXX=/usr/bin/clang++ \
  cmake --build /tmp/build/ \
  --parallel ${CORES} -t package 2>&1 | tee /tmp/cmake-output.txt
RUN mv /tmp/build/mariadb-${MARIADB_VER}*.tar.gz /tmp/mbd.tar.gz

FROM common AS runtime
ARG MARIADB_VER
ARG RUN_USER
ARG PUID
ARG PGID
ARG TZ
RUN \
  apt-get update \
  && apt-get install -y \
  # general libs
  gnutls-bin tzdata logrotate expect systemd \
  libreadline8 libxml2 unixodbc \
  zlib1g liblz4-1 libzstd1 libsnappy1v5 \
  libgoogle-perftools4 libjemalloc2 openssl \
  liburing1 libaio1 libpmem1 libnuma1
COPY --from=packager /tmp/mbd.tar.gz .
RUN tar -zpxf mbd.tar.gz --exclude "mysql-test" \
  && groupadd -g ${PGID} ${RUN_USER} \
  && useradd -u ${PUID} -g ${PGID} ${RUN_USER} \
  && mkdir -p /usr/local/mysql \
  && cp -a /tmp/mariadb-${MARIADB_VER}*-linux-x86_64/* /usr/local/mysql \
  && ln -s /usr/local/mysql/support-files/systemd/* /lib/systemd/system/ \
  && chown -R ${RUN_USER} /usr/local/mysql/ || true \
  && mkdir -p /etc/mysql/conf.d \
  && chown -R ${RUN_USER} /etc/mysql/conf.d/ \
  && mkdir -p /etc/security/limits.d \
  && rm -rf /tmp/*.tar.gz \
  && rm -rf /tmp/mariadb-${MARIADB_VER}*

COPY ./scripts /tmp/scripts
COPY ./my.cnf /etc/mysql/my.cnf
COPY ./logrotate /etc/logrotate.d/mariadb_slow_log
COPY ./99-mysql.conf /etc/security/limits.d/99-mysql.conf

ENV PATH="/usr/local/mysql/bin:$PATH"

ENTRYPOINT [ "/tmp/scripts/init.sh" ]

VOLUME [ "/usr/local/mysql/data" ]
VOLUME [ "/etc/mysql/conf.d" ]

EXPOSE 3306

# FROM scratch AS exporter2
# COPY --from=maker /tmp/cmake-options.txt .
# COPY --from=packager /tmp/cmake-output.txt .
# COPY --from=packager /tmp/mbd.tar.gz .
