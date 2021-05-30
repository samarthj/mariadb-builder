#!/bin/bash
apt-get install -y --no-install-recommends apt-transport-https curl gnupg ca-certificates git
curl -fsSL https://bazel.build/bazel-release.pub.gpg | gpg --dearmor >bazel.gpg
mv bazel.gpg /etc/apt/trusted.gpg.d/
echo "deb [arch=amd64] https://storage.googleapis.com/bazel-apt stable jdk1.8" >/etc/apt/sources.list.d/bazel.list
apt-get update -y
apt-get install -y --no-install-recommends bazel python3-distutils openjdk-11-jdk-headless
ln -s /usr/bin/python3 /usr/bin/python
cd /tmp || exit 1
[ -d abseil-cpp ] || git clone --depth=1 --recurse-submodules --shallow-submodules -j "${CORES}" "https://github.com/abseil/abseil-cpp.git"
cd abseil-cpp || exit 1
mkdir -p build
cd build || exit 1
cmake -DBUILD_TESTING=ON -DABSL_USE_GOOGLETEST_HEAD=ON -DCMAKE_INSTALL_PREFIX:PATH=/usr/local/abseil-cpp ..
make -j
# ctest
# ls -la /tmp/abseil-cpp/build
# ls -la /tmp/abseil-cpp/build/googletest-external
cd /tmp || exit 1
[ -d tcmalloc ] || git clone --depth=1 --recurse-submodules --shallow-submodules -j "${CORES}" "https://github.com/google/tcmalloc.git"
cd tcmalloc || exit 1
[ -d bazel-out ] || bazel test -c fastbuild --sandbox_debug --test_output=errors --build_tests_only //tcmalloc/...
bazel info -c dbg --show_make_env
# ls -la
cd /tmp || exit 1
