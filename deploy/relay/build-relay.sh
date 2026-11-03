#!/usr/bin/env bash
# build-relay.sh: build the room's relay (libcvc's arisrv) as a self-contained bundle, on catx-03,
# under its ramdisk (never in a home directory there: it is nearly full).
#
#   deploy/relay/build-relay.sh LIBCVC_REF NAME
#
# Checks transfix/libcvc out at LIBCVC_REF (a branch, tag or commit), builds arisrv with the
# conference transports (gRPC and WebSocket), Jolt avatars and libjpeg-turbo video rungs, and
# writes $WORK/NAME: bin/arisrv, lib/ (libcvc and every library it needs from the deps prefixes,
# found through RUNPATH $ORIGIN/../lib) and BUILT-FROM. deploy-relay.sh places it on paladin.
#
# arisrv has no cvcpkg package yet, so the relay is built here; the page is not (it is the stock
# arigl-web package).
set -euo pipefail
[[ $# -eq 2 ]] || { echo "usage: $0 LIBCVC_REF NAME" >&2; exit 2; }
REF=$1 NAME=$2
WORK=${WORK:-/mnt/ramdisk/tfx/cyprty-relay}
# The native deps (gRPC, protobuf, Jolt, ...; built once on catx-03) and libjpeg-turbo.
DEPS=${DEPS:-$HOME/h1-native-deps}
DEPS_EXTRA=${DEPS_EXTRA:-/mnt/ramdisk/tfx/relay-6977af28/deps-extra}
CMAKE=${CMAKE:-/opt/cvc-wasm/cmake-cvcpkg/bin/cmake}
test -f "$DEPS_EXTRA/lib/libturbojpeg.so" || { echo "FATAL: no libjpeg-turbo in $DEPS_EXTRA"; exit 1; }
export XDG_CACHE_HOME=$WORK/cache
mkdir -p "$WORK" "$WORK/cache"

echo "=== source: transfix/libcvc $REF ==="
SRC=$WORK/src
if [[ ! -d "$SRC/.git" ]]; then
  git clone --quiet --filter=blob:none https://github.com/transfix/libcvc.git "$SRC"
fi
git -C "$SRC" fetch --quiet origin "$REF"
git -C "$SRC" checkout --quiet --force FETCH_HEAD
COMMIT=$(git -C "$SRC" rev-parse --short HEAD)
echo "libcvc $COMMIT"

B=$WORK/build
echo "=== configure ==="
"$CMAKE" -G Ninja -S "$SRC" -B "$B" -DCMAKE_MAKE_PROGRAM=/usr/bin/ninja \
  -DCMAKE_BUILD_TYPE=Release -DBUILD_SHARED_LIBS=ON \
  "-DCMAKE_PREFIX_PATH=$DEPS;$DEPS_EXTRA" \
  '-DCMAKE_INSTALL_RPATH=$ORIGIN/../lib' \
  -DCVC_APP_XML_PROPERTY_TREE=OFF -DCVC_ARIADNE_TVISION=ON -DCVC_BUILD_ARI=ON \
  -DCVC_BUILD_ARIGL=OFF -DCVC_BUILD_ARISRV=ON -DCVC_BUILD_CLI=OFF -DCVC_BUILD_CVCGL=OFF \
  -DCVC_BUILD_LSYS_TOOLS=OFF -DCVC_BUILD_PHYSICS_REPLAY=OFF -DCVC_BUILD_PYCVC=OFF \
  -DCVC_BUILD_TESTS=OFF -DCVC_ENABLE_ASSIMP=ON -DCVC_ENABLE_COVERAGE=OFF -DCVC_ENABLE_CUDA=OFF \
  -DCVC_ENABLE_FFTW=OFF -DCVC_ENABLE_GRPC=ON -DCVC_ENABLE_IMAGEMAGICK=OFF -DCVC_ENABLE_LIBIGL=ON \
  -DCVC_ENABLE_MESHER=OFF -DCVC_ENABLE_OPENMP=OFF -DCVC_ENABLE_SDF=OFF -DCVC_ENABLE_WS=ON \
  -DCVC_FFT_PROVIDER=pocketfft -DCVC_GEOMETRY_CORRECT_INDEX_START=OFF \
  -DCVC_GEOMETRY_ENABLE_BUNNY=ON -DCVC_STATE_MEMORY_MANAGER=ON -DCVC_USING_IMOD_MRC=OFF \
  -DCVC_USING_XMLRPC=OFF -DCVC_WITH_JOLT=ON -DDISABLE_CGAL=ON > "$WORK/configure.log" 2>&1 ||
  { tail -40 "$WORK/configure.log"; exit 1; }
for want in "gRPC transport" "WebSocket transport ENABLED" "Jolt backend ENABLED"; do
  grep -qi "$want" "$WORK/configure.log" || { echo "FATAL: the configure did not report '$want'"; exit 1; }
done

echo "=== build arisrv ==="
"$CMAKE" --build "$B" --target arisrv -j "${JOBS:-10}" > "$WORK/build.log" 2>&1 ||
  { grep -E "error|FAILED" "$WORK/build.log" | head -30; exit 1; }
tail -1 "$WORK/build.log"

echo "=== bundle $NAME ==="
O=$WORK/$NAME
rm -rf "$WORK/install" "$O"
"$CMAKE" --install "$B" --prefix "$WORK/install" > /dev/null 2>&1 || true
mkdir -p "$O/bin" "$O/lib"
cp -a "$WORK/install/bin/arisrv" "$O/bin/"
cp -a "$WORK/install/lib"/libcvc.so* "$O/lib/"
LD_LIBRARY_PATH="$O/lib:$DEPS/lib:$DEPS_EXTRA/lib" ldd "$O/bin/arisrv" |
  awk '/=> \// {print $3}' | grep -F -e "$DEPS" -e "$DEPS_EXTRA" | sort -u |
  while read -r so; do cp -L "$so" "$O/lib/"; done
if LD_LIBRARY_PATH= ldd "$O/bin/arisrv" | grep "not found"; then echo "FATAL: unresolved libraries"; exit 1; fi
echo "libcvc $COMMIT ($REF), arisrv built on catx-03, glibc $(ldd --version | head -1 | awk '{print $NF}'), $(date -u +%Y-%m-%dT%H:%M:%SZ)" > "$O/BUILT-FROM"
cat "$O/BUILT-FROM"
echo "libs: $(ls "$O/lib" | wc -l)"
echo "RELAY_BUILD_OK $O"
