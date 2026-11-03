#!/usr/bin/env bash
# stage.sh: assemble the cyberpcangel.com payload from an arigl-web package and cyprty's documents.
#
#   deploy/cyberpcangel/stage.sh WEB_DIR DOCS_DIR OUT [BUILT_FROM]
#
# WEB_DIR is a single-threaded arigl-web package's share/arigl-web; DOCS_DIR is cyprty's
# share/cyprty. OUT is created (it must not exist) with the one site:
#
#   OUT/cyprty/   https://cyberpcangel.com/cyprty/   arigl-web's index.html running main.ari
#
# It gets the documents, ariadne.config.json (beside this script), the package's licenses and its
# page files. BUILT_FROM, if given, is written to .built-from: what the payload was built from,
# which the workflow reads back to skip a run when nothing moved.
#
# The package must be one that can run a conference: its page reads url_env (the config's ?name=
# and friends), and its arigl.wasm has the WebSocket transport. An older arigl-web would load the
# page and then never join the room, so this refuses it.
set -euo pipefail

[[ $# -ge 3 && $# -le 4 ]] || { echo "usage: $0 WEB_DIR DOCS_DIR OUT [BUILT_FROM]" >&2; exit 2; }
web=$1 docs=$2 out=$3 built_from=${4:-}
here=$(cd "$(dirname "$0")" && pwd)

for f in index.html arigl-web.js arigl-web.css arigl.js arigl.wasm LICENSE THIRD_PARTY_NOTICES.md; do
  [[ -e "$web/$f" ]] || { echo "stage: $web has no $f (a single-threaded arigl-web package?)" >&2; exit 1; }
done
grep -q 'url_env' "$web/arigl-web.js" ||
  { echo "stage: $web/arigl-web.js has no url_env: an arigl-web older than the conference page config" >&2; exit 1; }
grep -q 'emscripten_websocket' "$web/arigl.js" ||
  { echo "stage: $web/arigl.js has no WebSocket support: an arigl-web built without CVC_ENABLE_WS" >&2; exit 1; }
[[ -f "$docs/main.ari" ]] || { echo "stage: $docs has no main.ari" >&2; exit 1; }
[[ ! -e "$out" ]] || { echo "stage: $out already exists" >&2; exit 1; }

dir="$out/cyprty"
install -d "$dir"
cp -R "$docs/." "$dir/"
install -m 644 "$here/ariadne.config.json" "$web/LICENSE" "$web/THIRD_PARTY_NOTICES.md" "$dir/"
for f in index.html arigl-web.js arigl-web.css arigl.js arigl.wasm; do cp "$web/$f" "$dir/"; done
if [[ -n "$built_from" ]]; then printf '%s\n' "$built_from" > "$dir/.built-from"; fi

chmod -R u=rwX,go=rX "$out"
echo "staged $(find "$out" -type f | wc -l) files, $(du -sh "$out" | cut -f1), in $out"
