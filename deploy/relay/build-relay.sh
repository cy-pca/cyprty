#!/usr/bin/env bash
# build-relay.sh: make the room's relay (libcvc's arisrv, from its cvcpkg package) into a
# self-contained bundle, on catx-03, under its ramdisk (never in a home directory there: it is
# nearly full).
#
#   deploy/relay/build-relay.sh VERSION NAME
#
# VERSION is a libcvc release: 3.7.10, or 3.7.10+cvc.1 for one arisrv revision. `cvcpkg install`
# puts that arisrv and the libcvc of the same release, with libcvc's runtime closure (gRPC,
# protobuf, Jolt, libjpeg-turbo, ...), into the cvcpkg prefix $WORK/NAME.prefix. libcvc is pinned
# beside arisrv because the arisrv package leaves it unpinned: an older arisrv with the newest
# libcvc would not match its ABI.
#
# The prefix is ~550 MB, most of it headers, static libraries and tools. The bundle, $WORK/NAME,
# takes only what the relay runs: bin/arisrv, the libraries it loads in lib/ (the package's
# RUNPATH is $ORIGIN/../lib), and BUILT-FROM. deploy-relay.sh places it on paladin.
set -euo pipefail
[[ $# -eq 2 ]] || { echo "usage: $0 VERSION NAME" >&2; exit 2; }
VER=$1 NAME=$2
WORK=${WORK:-/mnt/ramdisk/tfx/cyprty-relay}
# `ssh catx-03 'bash -s'` gets no ~/.local/bin on PATH, where catx-03's cvcpkg is.
CVCPKG=${CVCPKG:-$(command -v cvcpkg || echo "$HOME/.local/bin/cvcpkg")}
# cvcpkg's download cache too.
export XDG_CACHE_HOME=$WORK/cache
mkdir -p "$WORK" "$WORK/cache"

P=$WORK/$NAME.prefix
echo "=== cvcpkg install arisrv==$VER libcvc==${VER%%+*} ==="
rm -rf "$P"
"$CVCPKG" install "arisrv==$VER" "libcvc==${VER%%+*}" --prefix "$P" \
  --platform linux --config release --link shared --no-fallback-to-source \
  > "$WORK/$NAME.install.log" 2>&1 || { tail -20 "$WORK/$NAME.install.log"; exit 1; }
installed() { "$CVCPKG" list --installed --prefix "$P" | awk -v n="$1" '$1 == n {print $2}'; }
ARISRV=$(installed arisrv) LIBCVC=$(installed libcvc)
[[ -n "$ARISRV" && -n "$LIBCVC" ]] || { echo "FATAL: no arisrv or no libcvc in $P"; exit 1; }
[[ "${ARISRV%%+*}" == "${LIBCVC%%+*}" ]] ||
  { echo "FATAL: arisrv $ARISRV and libcvc $LIBCVC are from different releases"; exit 1; }
echo "arisrv $ARISRV, libcvc $LIBCVC"

echo "=== bundle $NAME ==="
O=$WORK/$NAME
rm -rf "$O"
mkdir -p "$O/bin" "$O/lib"
cp -L "$P/bin/arisrv" "$O/bin/"
readelf -d "$O/bin/arisrv" | grep -q 'RUNPATH.*\$ORIGIN/\.\./lib' ||
  { echo "FATAL: arisrv's RUNPATH is not \$ORIGIN/../lib"; exit 1; }
LD_LIBRARY_PATH= ldd "$P/bin/arisrv" | awk '/=> \// {print $3}' | grep -F "$P/" | sort -u |
  while read -r so; do cp -L "$so" "$O/lib/"; done
if LD_LIBRARY_PATH= ldd "$O/bin/arisrv" | grep "not found"; then echo "FATAL: unresolved libraries"; exit 1; fi
echo "arisrv $ARISRV, libcvc $LIBCVC (cvcpkg linux $(uname -m) release shared), bundled on catx-03, glibc $(ldd --version | head -1 | awk '{print $NF}'), $(date -u +%Y-%m-%dT%H:%M:%SZ)" > "$O/BUILT-FROM"
cat "$O/BUILT-FROM"
echo "libs: $(ls "$O/lib" | wc -l), $(du -sh "$O" | cut -f1)"
rm -rf "$P"
echo "RELAY_BUILD_OK $O"
