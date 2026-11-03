#!/usr/bin/env bash
# cyprty-deploy.sh: runs INSIDE the cyberpcangel instance as root, installed at
# /root/cyprty-deploy.sh. Only the catx-00 forced command runs it (txwtf-deploy-cyberpcangel,
# action deploy-cyprty), with a payload tarball (tar czf) on stdin:
#
#   cyprty/   -> $DOCROOT/cyprty   https://cyberpcangel.com/cyprty/
#
# The payload is static files only. Nothing in it runs: this script owns the Apache config
# (conf-available/cyprty.conf, including the /cyprty-ws tunnel to the relay), and it refuses a
# payload that has anything but plain files and directories, or a file type a browser page doesn't
# need (no .php, no .htaccess). The site is replaced whole, by a rename; the previous one stays as
# $DOCROOT/cyprty.prev for a rollback by hand. The files are owned by root, so the web server
# (WordPress runs as www-data) can't change them.
#
# Version of record: cy-pca/cyprty deploy/cyberpcangel/cyprty-deploy.sh. Install or update it:
#   ssh tfx@catx-00.tx.wtf 'lxc exec cyberpcangel --project catx -- bash -c "cat > /root/cyprty-deploy.sh.new && bash -n /root/cyprty-deploy.sh.new && chmod 700 /root/cyprty-deploy.sh.new && mv /root/cyprty-deploy.sh.new /root/cyprty-deploy.sh && echo OK"' \
#     < deploy/cyberpcangel/cyprty-deploy.sh
set -euo pipefail
umask 022

SITE=cyprty
# The relay's WebSocket acceptor (arisrv --ws-listen on paladin; deploy/relay). The page dials
# wss://<this host>/cyprty-ws, which Apache tunnels here.
RELAY_WS=${CYPRTY_RELAY_WS:-ws://paladin.sublevels.net:7702/}
MAX_BYTES=$((512 * 1024 * 1024))
# Overridable only so the script can be tested off the box; the forced command sets neither.
APACHE=${CYPRTY_APACHE_ETC:-/etc/apache2}
TMPBASE=${CYPRTY_TMPDIR:-/root}

WORK=$(mktemp -d "$TMPBASE/cyprty-payload.XXXXXX")
trap 'rm -rf "$WORK"' EXIT

echo "### payload"
tar xzf - -C "$WORK" --no-same-owner --no-same-permissions
[[ -d "$WORK/$SITE" ]] || { echo "FATAL: payload has no $SITE/"; exit 1; }
extra=$(find "$WORK" -mindepth 1 -maxdepth 1 ! -name "$SITE" -print)
[[ -z "$extra" ]] || { echo "FATAL: payload has more than $SITE: $extra"; exit 1; }
odd=$(find "$WORK" -mindepth 1 ! -type f ! -type d -print)
[[ -z "$odd" ]] || { echo "FATAL: payload has links or special files: $odd"; exit 1; }
bad=$(find "$WORK" -type f ! \( -name '*.html' -o -name '*.js' -o -name '*.css' -o -name '*.wasm' \
        -o -name '*.json' -o -name '*.ari' -o -name '*.md' -o -name '*.txt' -o -name '*.png' \
        -o -name '*.jpg' -o -name '*.svg' -o -name 'LICENSE*' -o -name '.built-from' \) -print)
[[ -z "$bad" ]] || { echo "FATAL: payload has files a page doesn't serve: $bad"; exit 1; }
[[ -f "$WORK/$SITE/index.html" && -f "$WORK/$SITE/main.ari" ]] ||
  { echo "FATAL: payload has no index.html or main.ari"; exit 1; }
bytes=$(du -sb "$WORK" | cut -f1)
(( bytes <= MAX_BYTES )) || { echo "FATAL: payload is $bytes bytes, over $MAX_BYTES"; exit 1; }
echo "payload ok: $(find "$WORK" -type f | wc -l) files, $bytes bytes"

echo "### docroot (the enabled vhost that holds wp-config.php)"
DOCROOT=""
CANDS=$(grep -RhE '^[[:space:]]*DocumentRoot' "$APACHE/sites-enabled/" 2>/dev/null \
          | awk '{print $2}' | tr -d '"' | sort -u || true)
for c in $CANDS; do [[ -f "$c/wp-config.php" ]] && { DOCROOT="$c"; break; }; done
[[ -n "$DOCROOT" ]] || { echo "FATAL: no enabled-vhost DocumentRoot has wp-config.php (candidates: ${CANDS:-none})"; exit 1; }
echo "DOCROOT=$DOCROOT"

echo "### apache config"
for m in headers deflate proxy proxy_wstunnel; do
  apache2ctl -M 2>/dev/null | grep -q "${m}_module" || a2enmod -q "$m"
done
CONF="$APACHE/conf-available/cyprty.conf"
NEW=$(mktemp)
cat > "$NEW" <<CONF
# Written by /root/cyprty-deploy.sh (cy-pca/cyprty deploy/cyberpcangel). Edit that, not this.
# The page: the stock arigl-web page and cyprty's documents. Cross-origin isolated (scoped to this
# directory) so a threaded build gets SharedArrayBuffer; harmless for the single-threaded one.
<Directory "$DOCROOT/$SITE">
    Options -Indexes -ExecCGI +FollowSymLinks
    AllowOverride None
    Require all granted
    DirectoryIndex index.html
    <IfModule mod_rewrite.c>
        RewriteEngine Off
    </IfModule>
    AddType application/wasm .wasm
    AddType text/plain .ari
    AddCharset utf-8 .ari .json .js .css .html .md
    <IfModule mod_deflate.c>
        AddOutputFilterByType DEFLATE application/wasm application/javascript text/javascript text/html text/css text/plain application/json
    </IfModule>
    Header always set Cross-Origin-Opener-Policy "same-origin"
    Header always set Cross-Origin-Embedder-Policy "require-corp"
    Header always set Cross-Origin-Resource-Policy "same-origin"
    Header always set X-Content-Type-Options "nosniff"
    Header always set Referrer-Policy "no-referrer"
    # A redeploy shows on the next load: every file revalidates (304 when unchanged).
    Header set Cache-Control "no-cache"
</Directory>

# The relay: the page dials wss://<this host>/cyprty-ws, tunnelled to arisrv's WebSocket acceptor.
# ProxyPass is matched before WordPress's rewrites, so /cyprty-ws never reaches index.php. Global
# scope, so it applies to the TLS vhost.
<IfModule mod_proxy_wstunnel.c>
    ProxyPass        /cyprty-ws  $RELAY_WS  upgrade=websocket
    ProxyPassReverse /cyprty-ws  $RELAY_WS
</IfModule>
CONF
if [[ -f "$CONF" ]] && cmp -s "$NEW" "$CONF"; then
  echo "unchanged: $CONF"
  rm -f "$NEW"
  CONF_CHANGED=0
else
  [[ -f "$CONF" ]] && cp -a "$CONF" "$CONF.prev"
  install -m 644 "$NEW" "$CONF"; rm -f "$NEW"
  a2enconf -q cyprty
  if ! apache2ctl configtest; then
    echo "FATAL: configtest failed; restoring the previous config"
    if [[ -f "$CONF.prev" ]]; then mv "$CONF.prev" "$CONF"; else a2disconf -q cyprty; rm -f "$CONF"; fi
    exit 1
  fi
  CONF_CHANGED=1
fi

echo "### place the site"
dst="$DOCROOT/$SITE" prev="$DOCROOT/$SITE.prev"
tmp="$DOCROOT/.$SITE.new.$$"
rm -rf "$tmp"
cp -R "$WORK/$SITE" "$tmp"
chown -R root:root "$tmp"
chmod -R u=rwX,go=rX "$tmp"
kept=""
if [[ -e "$dst" ]]; then rm -rf "$prev"; mv "$dst" "$prev"; kept=" (the previous one is $prev)"; fi
mv "$tmp" "$dst"
echo "$SITE: $(find "$dst" -type f | wc -l) files$kept"

if (( CONF_CHANGED )); then systemctl reload apache2; echo "apache reloaded"; fi
echo "REMOTE_DONE DOCROOT=$DOCROOT SITE=$SITE"
