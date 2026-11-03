# cyprty roadmap

## 1. Off libcvc's own build, onto the stock page

Until now cyprty was a separate wasm build inside libcvc (`cyprty`, with its own page), deployed
by hand. It now becomes documents run by the stock `arigl-web` package. What that takes:

- [ ] libcvc: the stock page reads what a conference client needs from its config (`{ws_origin}`,
      `url_env`, `fragment_env`, `device_identity`, the audio unlock, `fullscreen_button`), and
      the `arigl-web` recipe builds the single-threaded package with the WebSocket transport, Jolt,
      Opus and device keys.
- [ ] cvcpkg.org: a wasm `protobuf` (cy-pca/cvcpkg recipe, merged in #452, never published for
      wasm), then a libcvc release whose `arigl-web` has the above.
- [ ] catx-00: the `deploy-cyprty` forced-command action, and `/root/cyprty-deploy.sh` in the
      cyberpcangel instance ([deploy/cyberpcangel/README.md](../deploy/cyberpcangel/README.md)).
- [ ] The first deploy from this repository, then the `workflow_run` trigger (deploy after `ci`
      on a push to main), as cy-pca/nicotina has.
- [ ] libcvc drops its `cyprty` build target and page.
- [ ] `ci` runs the documents: a packaged arigl joining a local relay.

## 2. Built on the baseline

libcvc keeps the reusable conference components (camera, avatar, users, chat, ...) and a baseline
Ariadne conference app. When that app ships as a `cvc://` document, `main.ari` loads it instead
of carrying a copy, and adds cyprty's own windows and branding.

## 3. A branded app

cyprty's own look and name, beyond the baseline.
