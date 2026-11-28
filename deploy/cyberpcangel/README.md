# cyprty on cyberpcangel.com

https://cyberpcangel.com/cyprty/: the stock `arigl-web` page running `main.ari`, public and not
login-gated. The page dials the room's relay at `wss://cyberpcangel.com/cyprty-ws`, which Apache
tunnels to arisrv on paladin ([../relay/README.md](../relay/README.md)).

## How it deploys

cy-pca/ops deploys the site. It is the private repo that holds cy-pca's production deploys and
their keys; its `cyberpcangel-deploy` workflow (site `cyprty`) runs on that repo's own runner, and
its `cyberpcangel/README.md` has the chain, the secrets and the host setup. It runs by hand only,
with `ref` for the documents to publish and, optionally, `arigl_web` for the package version (the
newest when empty), the same chain as cy-pca/nicotina's. This directory is what the payload is made
of: ops runs `stage.sh` and `verify.py` from the commit it deploys. Deploy the relay first when the
page needs a newer one ([../relay/README.md](../relay/README.md)):

```
ops-deploy-00 (catx-01): cy-pca/ops's runner, label deploy
  cvcpkg install   arigl-web (wasm, single-threaded) from cvcpkg.org
  stage.sh         + share/cyprty + ariadne.config.json            -> payload/cyprty
  tar czf - | ssh tfx@catx-00 deploy-cyprty      (a key that only ops' cyberpcangel environment has)
catx-00 forced command (~tfx/bin/txwtf-deploy-cyberpcangel)
  deploy-cyprty -> lxc exec cyberpcangel --project catx -- /root/cyprty-deploy.sh
cyberpcangel instance
  cyprty-deploy.sh  checks the payload, replaces $DOCROOT/cyprty (the previous site stays as
                    $DOCROOT/cyprty.prev), owns /etc/apache2/conf-available/cyprty.conf
verify.py          every staged file served byte for byte, scripts as JavaScript, the headers,
                   the redirect
```

- **The stock page.** The page is the `arigl-web` package as cvcpkg.org publishes it, not a
  build of libcvc. A libcvc feature reaches the site when a libcvc release publishes it.
- **Only a package that can run a conference.** `stage.sh` refuses an `arigl-web` whose page has
  no `url_env` config or whose `arigl.wasm` has no WebSocket transport: it would load and never
  join the room.
- **The AudioWorklets, when the package has them.** An `arigl-web` from transfix/libcvc#1412 on
  runs the mic and speaker on AudioWorklets, off the main thread, and ships their processors as
  `cvc-audio-worklet.js`; `stage.sh` copies the file when the package has it. A page that loads
  the file and finds none uses the copy compiled into `arigl.wasm`, from a `blob:` URL (this site
  has no Content-Security-Policy), after a 404. `?audio=sdl` puts them back on SDL's
  ScriptProcessorNode, for an A/B.
- **Only when something moved.** `.built-from`'s first word fingerprints the arigl-web bundle, the
  documents and the files that shape the payload (`ariadne.config.json`, `stage.sh`, ops'
  workflow). A run that matches the live one stops; `force` publishes anyway.
- **The payload runs nothing.** `cyprty-deploy.sh` is installed once and fixed. It refuses links,
  special files and any file a page doesn't serve, writes the Apache config itself, and leaves the
  files owned by root.
- **Apache** (`cyprty.conf`): the directory (`application/wasm`, deflate, no listings, no
  rewrites into WordPress, `Cache-Control: no-cache`, cross-origin isolation headers) and the
  `/cyprty-ws` WebSocket tunnel to `ws://paladin.sublevels.net:7702/`.

## Setup

cy-pca/ops `cyberpcangel/README.md` has it: the key in ops' `cyberpcangel` environment (catx-00
takes it only from ops' runner, behind the forced command), the forced command's `deploy-cyprty`
action, and `/root/cyprty-deploy.sh`. That script's version of record is cy-pca/ops
`cyberpcangel/cyprty-deploy.sh`. The copy here is byte-identical, and CI runs it on a fake
instance; ops' deploy warns when the two differ. A change goes into both, then is installed on the
box from ops (the command at the top of the script). The script prints its own sha256, and the
deploy warns when the installed one isn't the record.

Until 2026-11-28 this repository deployed the site itself, with a `deploy-cyberpcangel` workflow
on catx-03's cy-pca org runner and that host's `id_ed25519_cyberpcangel_deploy`.

## By hand

With the house access (`tfx` on catx-00) instead of the deploy key:

```bash
bash deploy/cyberpcangel/stage.sh <prefix>/share/arigl-web share/cyprty payload
tar czf - -C payload cyprty \
  | ssh tfx@catx-00.tx.wtf 'lxc exec cyberpcangel --project catx -- /root/cyprty-deploy.sh'
python3 deploy/cyberpcangel/verify.py payload
```

Rolling back to the previous site:

```bash
ssh tfx@catx-00.tx.wtf 'lxc exec cyberpcangel --project catx -- bash -c "D=/var/www/cyberpcangel.com; mv \$D/cyprty \$D/cyprty.rolledback && mv \$D/cyprty.prev \$D/cyprty"'
```
