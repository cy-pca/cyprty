# cyprty on cyberpcangel.com

https://cyberpcangel.com/cyprty/: the stock `arigl-web` page running `main.ari`, public and not
login-gated. The page dials the room's relay at `wss://cyberpcangel.com/cyprty-ws`, which Apache
tunnels to arisrv on paladin ([../relay/README.md](../relay/README.md)).

## How it deploys

The [deploy-cyberpcangel](../../.github/workflows/deploy-cyberpcangel.yml) workflow publishes the
documents with the newest `arigl-web` from cvcpkg.org. It runs by hand for now (Actions ->
deploy-cyberpcangel -> Run workflow, with `ref` for the documents to publish), the same chain as
cy-pca/nicotina's:

```
catx-03 runner (label cvcpkg-prod: the cy-pca org runner catx-03-cy-pca, user github-runner)
  cvcpkg install   arigl-web (wasm, single-threaded) from cvcpkg.org
  stage.sh         + share/cyprty + ariadne.config.json            -> payload/cyprty
  tar czf - | ssh -i ~/.ssh/id_ed25519_cyberpcangel_deploy tfx@catx-00.tx.wtf deploy-cyprty
catx-00 forced command (~tfx/bin/txwtf-deploy-cyberpcangel)
  deploy-cyprty -> lxc exec cyberpcangel --project catx -- /root/cyprty-deploy.sh
cyberpcangel instance
  cyprty-deploy.sh  checks the payload, replaces $DOCROOT/cyprty (the previous site stays as
                    $DOCROOT/cyprty.prev), owns /etc/apache2/conf-available/cyprty.conf
verify.py          every staged file served byte for byte, the headers, the redirect
```

- **The stock page.** The page is the `arigl-web` package as cvcpkg.org publishes it, not a
  build of libcvc. A libcvc feature reaches the site when a libcvc release publishes it.
- **Only a package that can run a conference.** `stage.sh` refuses an `arigl-web` whose page has
  no `url_env` config or whose `arigl.wasm` has no WebSocket transport: it would load and never
  join the room.
- **Only when something moved.** `.built-from`'s first word fingerprints the arigl-web bundle, the
  documents and the files that shape the payload (`ariadne.config.json`, `stage.sh`, the
  workflow). A run that matches the live one stops; `force` publishes anyway.
- **The payload runs nothing.** `cyprty-deploy.sh` is installed once and fixed. It refuses links,
  special files and any file a page doesn't serve, writes the Apache config itself, and leaves the
  files owned by root.
- **Apache** (`cyprty.conf`): the directory (`application/wasm`, deflate, no listings, no
  rewrites into WordPress, `Cache-Control: no-cache`, cross-origin isolation headers) and the
  `/cyprty-ws` WebSocket tunnel to `ws://paladin.sublevels.net:7702/`.

## One-time setup

Each needs the owner of catx-00 and the cyberpcangel instance:

1. Install the instance script:
   ```bash
   ssh tfx@catx-00.tx.wtf 'lxc exec cyberpcangel --project catx -- bash -c "cat > /root/cyprty-deploy.sh.new && bash -n /root/cyprty-deploy.sh.new && chmod 700 /root/cyprty-deploy.sh.new && mv /root/cyprty-deploy.sh.new /root/cyprty-deploy.sh && echo OK"' \
     < deploy/cyberpcangel/cyprty-deploy.sh
   ```
2. Add the action to the forced command `~tfx/bin/txwtf-deploy-cyberpcangel` on catx-00:
   ```
   deploy-cyprty)  exec lxc exec cyberpcangel --project catx -- /root/cyprty-deploy.sh ;;
   ```
3. Give this repository the cy-pca org runner group that holds catx-03-cy-pca.

## By hand

```bash
bash deploy/cyberpcangel/stage.sh <prefix>/share/arigl-web share/cyprty payload
tar czf - -C payload cyprty | ssh tfx@catx-00.tx.wtf deploy-cyprty
python3 deploy/cyberpcangel/verify.py payload
```

Rolling back to the previous site:

```bash
ssh tfx@catx-00.tx.wtf 'lxc exec cyberpcangel --project catx -- bash -c "D=/var/www/cyberpcangel.com; mv \$D/cyprty \$D/cyprty.rolledback && mv \$D/cyprty.prev \$D/cyprty"'
```
