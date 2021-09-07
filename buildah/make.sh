#!/bin/bash

mkdir -p /tmp/build
cd /tmp/build || exit 1
ls -la
# cmake --target clean /tmp/server
rm -rf /tmp/build/*

sed -i 's|<bson.h>|<bson/bson.h>|g' /tmp/server/storage/connect/cmgoconn.h
sed -i 's|<mongoc.h>|<mongoc/mongoc.h>|g' /tmp/server/storage/connect/cmgoconn.h
sed -i 's|#include <bcon.h>||g' /tmp/server/storage/connect/cmgoconn.h
sed -i 's|SetValue(bson_iter_int64(\&Desc))|SetValue(longlong(bson_iter_int64(\&Desc)))|g' /tmp/server/storage/connect/cmgoconn.cpp
sed -i 's|SetValue(bson_iter_date_time(\&Desc) / 1000)|SetValue(longlong(bson_iter_date_time(\&Desc) / 1000))|g' /tmp/server/storage/connect/cmgoconn.cpp
sed -i 's|IF (NOT JAVA_FOUND AND JNI_FOUND)|IF (NOT JAVA_FOUND AND NOT JNI_FOUND)|g' /tmp/server/storage/connect/CMakeLists.txt

# export CC=/usr/bin/clang
# export CXX=/usr/bin/clang++

cmake_options=(
  -Wno-dev
  # -Wno-error=dev
  # -Wnostringop-truncation
  # -DCMAKE_USER_MAKE_RULES_OVERRIDE='/tmp/CMakeExtra.txt'
  -DCMAKE_EXE_LINKER_FLAGS='-ltcmalloc' # -I/usr/include/libbson-1.0 -lbson-1.0 -I/usr/include/libmongoc-1.0 -lmongoc-1.0'
  # -DINSTALL_UNIX_ADDRDIR=/var/lib/mysql/mysql.sock
  # -DCMAKE_C_COMPILER=clang
  # -DCMAKE_CXX_COMPILER=clang++
  -DWITH_NUMA=ON
  -DWITH_PMEM=ON
  -DWITH_SAFEMALLOC=OFF    #using tcmalloc
  -DCONC_WITH_UNITTEST=OFF #unnecessary for release
  -DWITH_UNIT_TESTS=OFF    #unnecessary for release
  # -DWITH_EMBEDDED_SERVER=OFF #unnecessary for release
  -DWITH_WSREP=OFF
  -DCMAKE_BUILD_TYPE=MinSizeRel
  # -DCMAKE_BUILD_TYPE=RelWithDebInfo
  -DPLUGIN_ARCHIVE=STATIC
  # -DPLUGIN_AUTH_0X0100=NO
  -DPLUGIN_AUTH_ED25519=NO
  -DPLUGIN_AUTH_GSSAPI=NO
  # -DPLUGIN_AUTH_PAM=NO
  # -DPLUGIN_AUTH_PAM_V1=NO
  -DPLUGIN_AUTH_TEST_PLUGIN=NO #unnecessary for release
  -DPLUGIN_BLACKHOLE=NO        #unnecessary for release
  -DPLUGIN_CONNECT=YES
  # -DPLUGIN_CRACKLIB_PASSWORD_CHECK=NO
  -DPLUGIN_DAEMON_EXAMPLE=NO #unnecessary for release
  # -DPLUGIN_DEBUG_KEY_MANAGEMENT=STATIC
  -DPLUGIN_DIALOG_EXAMPLES=NO #unnecessary for release
  -DPLUGIN_DISKS=STATIC
  -DPLUGIN_EXAMPLE=NO                #unnecessary for release
  -DPLUGIN_EXAMPLE_KEY_MANAGEMENT=NO #unnecessary for release
  # -DPLUGIN_FEDERATED=STATIC
  -DPLUGIN_FEDERATEDX=YES # does not  build statically
  -DPLUGIN_FEEDBACK=NO    #unnecessary for release
  # -DPLUGIN_FILE_KEY_MANAGEMENT=DYNAMIC #unnecessary for release
  -DPLUGIN_FTEXAMPLE=NO #unnecessary for release
  -DPLUGIN_HANDLERSOCKET=YES
  -DPLUGIN_METADATA_LOCK_INFO=STATIC
  -DPLUGIN_MROONGA=STATIC
  -DPLUGIN_OQGRAPH=STATIC
  -DPLUGIN_QUERY_CACHE_INFO=STATIC
  -DPLUGIN_QUERY_RESPONSE_TIME=STATIC
  -DPLUGIN_ROCKSDB=YES # does not build statically
  -DPLUGIN_S3=STATIC
  -DPLUGIN_SEQUENCE=STATIC
  -DPLUGIN_SPIDER=NO
  -DPLUGIN_SPHINX=NO
  -DPLUGIN_SQL_ERRLOG=STATIC
  -DPLUGIN_TEST_SQL_DISCOVERY=NO #unnecessary for release
  -DPLUGIN_TEST_SQL_SERVICE=NO   #unnecessary for release
  -DPLUGIN_TEST_VERSIONING=NO    #unnecessary for release
  # -DTMPDIR=/tmp
  -DCONNECT_WITH_MONGO=ON
  -DWITH_INNODB_LZ4=ON
  -DWITH_ROCKSDB_JEMALLOC=ON
  -DWITH_ROCKSDB_LZ4=ON
  -DWITH_ROCKSDB_ZSTD=ON
  # -DWITH_ROCKSDB_snappy=OFF
  -DMYSQL_MAINTAINER_MODE=NO #unnecessary for release
  # -DWITH_LIBWRAP=ON
  -DWITH_READLINE=ON
  -DWITH_URING=ON
  # -DWITH_VALGRIND=ON
  -DAWS_SDK_EXTERNAL_PROJECT=ON
)

cmake -LAH --parallel="${CORES}" -GNinja "${cmake_options[@]}" /tmp/server 2>&1 | tee /tmp/up/ubuntu/cmake-options.txt
# cmake -B /tmp/build -S /tmp/server -DCMAKE_EXE_LINKER_FLAGS='-ltcmalloc' -Wno-dev -DWITH_SAFEMALLOC=OFF -DCMAKE_BUILD_TYPE=MinSizeRel -DWITH_URING=ON -DWITH_UNIT_TESTS=OFF -DWITH_WSREP=OFF -DTMPDIR=/tmp -DCONNECT_WITH_MONGO=ON -DWITH_ROCKSDB_JEMALLOC=ON -LAH 2>&1 | tee /tmp/up/ubuntu/cmake-options.txt

cmake --build /tmp/build --parallel "${CORES}" --target package | tee /tmp/up/ubuntu/cmake-output.txt
