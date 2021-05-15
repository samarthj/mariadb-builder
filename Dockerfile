ARG MARIADB_VER="10.5.10"
ARG RUN_USER="mysql"
ARG PUID=40
ARG PGID=40

FROM alpine:3.13 AS sourcer
ARG MARIADB_VER
WORKDIR /tmp
RUN wget https://downloads.mariadb.org/interstitial/mariadb-10.5.10/source/mariadb-${MARIADB_VER}.tar.gz -O /tmp/mdb.tar.gz
RUN tar -xf /tmp/mdb.tar.gz -C /tmp/ \
&& mv /tmp/mariadb-${MARIADB_VER} /tmp/server
# git clone -o tags -b mariadb-${MARIADB_VER} -j 4 --depth 1 --shallow-submodules https://github.com/MariaDB/server.git \
# && cd server \
# && git submodule update --init --recursive -j 12

FROM sourcer AS builder
RUN \
apk add --no-cache \
git gnupg openssl \
build-base clang-dev \
samurai cmake extra-cmake-modules ccache \
ncurses-dev gnutls-dev bison curl-dev libxml2-dev linux-headers \
boost-dev libaio-dev flex libbson-dev linux-pam-dev \
lz4-dev zstd-dev zlib-dev xz-libs readline unixodbc libevent-dev \
&& apk update && apk upgrade

FROM builder AS packager
RUN \
mkdir /tmp/build && cd /tmp/build \
&& cmake ../server -DCONC_WITH_{UNITTEST,SSL}=OFF -DWITH_EMBEDDED_SERVER=ON -DWITH_UNIT_TESTS=OFF -DCMAKE_BUILD_TYPE=Release -DPLUGIN_{ARCHIVE,TOKUDB,MROONGA,OQGRAPH,SPIDER,SPHINX}=NO -DWITH_SAFEMALLOC=OFF -DWITH_SSL=bundled -DMYSQL_MAINTAINER_MODE=OFF -G Ninja
RUN  cmake --build /tmp/build/ --parallel 24 -t package

FROM alpine:latest AS runtime
ARG MARIADB_VER
ARG RUN_USER
ARG PUID
ARG PGID
COPY --from=packager /tmp/build/mariadb-${MARIADB_VER}-linux-x86_64.tar.gz /tmp/mariadb.tar.gz
RUN cd /tmp && tar -xf mariadb.tar.gz && rm -f mariadb.tar.gz \
#&& rm -rf /tmp/mariadb-${MARIADB_VER}-linux-x86_64/mysql-test \
&& echo ${RUN_USER} ${PUID} ${PGID} \
&& addgroup -S -g ${PGID} ${RUN_USER} \
&& adduser -S -D -H -u ${PUID} -G ${RUN_USER} -g "MySQL" ${RUN_USER} \
&& apk add --no-cache bash gnutls libevent unixodbc lz4-libs zstd-libs openssl libaio readline libxml2 libaio xz-libs zlib gcc g++ \
&& mkdir -p /usr/local/mysql \
&& cp -a /tmp/mariadb-${MARIADB_VER}-linux-x86_64/* /usr/local/mysql \
&& chown -R ${RUN_USER} /usr/local/mysql/ || true \
&& rm -rf /tmp/mariadb-${MARIADB_VER}-linux-x86_64 \
&& mkdir -p /etc/mysql/conf.d \
&& chown -R ${RUN_USER} /etc/mysql/conf.d/

COPY ./scripts /tmp/scripts
COPY ./my.cnf /etc/mysql/my.cnf

ENV PATH="/usr/local/mysql/bin:$PATH"

ENTRYPOINT [ "/tmp/scripts/init.sh" ]

VOLUME [ "/usr/local/mysql/data" ]
VOLUME [ "/etc/mysql/conf.d" ]

EXPOSE 3306


