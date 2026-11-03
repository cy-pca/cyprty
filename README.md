# cyprty

cyprty is a conference room you walk around in: an avatar for everyone, live camera and
microphone, written as [Ariadne](https://github.com/transfix/libcvc/blob/master/docs/ARIADNE.md)
documents. It runs live at **https://cyberpcangel.com/cyprty/**.

This repository holds only cyprty's documents and how they are deployed. Everything else comes
from [libcvc](https://github.com/transfix/libcvc), through its published packages:

| | from |
|---|---|
| the documents (`share/cyprty/`) | this repository |
| the browser host (`index.html`, `arigl.wasm`, ...) | libcvc's `arigl-web` package on cvcpkg.org: the stock page, not a build of libcvc |
| the conference itself: rooms, relays, holons, avatar physics, camera and microphone streams | libcvc (cvc::ariadne, cvc::state, cvcGL), in that package |
| the relay | libcvc's `arisrv` (deploy/relay builds it until it has a package) |

cyprty starts as libcvc's baseline Ariadne conference app. It will grow its own windows and
branding on top of that baseline ([docs/ROADMAP.md](docs/ROADMAP.md)).

## Layout

```
share/cyprty/main.ari          the app
web/ariadne.config.json        the page config, for serving the app yourself
deploy/cyberpcangel/           how https://cyberpcangel.com/cyprty/ is published (README there)
deploy/relay/                  how the room's relay is built and run (README there)
.github/workflows/             ci (the documents, configs and scripts), deploy-cyberpcangel, llm-gate
```

## Running it in a browser

Serve the `arigl-web` package's page files beside the documents and the page config, then open
the directory:

```bash
cvcpkg install arigl-web --platform wasm --arch wasm32 --link static --prefix ./deps
mkdir -p site && cp ./deps/share/arigl-web/{index.html,arigl-web.js,arigl-web.css,arigl.js,arigl.wasm} site/
cp share/cyprty/*.ari web/ariadne.config.json site/
python3 -m http.server 8080 --directory site
```

The page dials the relay at `{ws_origin}/cyprty-ws`, the same host it is served from. A local
relay is reached with `?relay=`:
`http://localhost:8080/?relay=ws://127.0.0.1:7702`.

The page config ([web/ariadne.config.json](web/ariadne.config.json)) sets what a link may change:

| URL | does |
|---|---|
| `?name=Alice` | your name in the room (otherwise `guest-xxxxx`) |
| `?relay=ws://host:port` | another relay (`ws://` or `wss://`) |
| `?look=mouse` / `?look=drag` | start in mouse look or drag to look |
| `?synthetic=1` | a test pattern instead of your camera |
| `?lane=1` | offer the relay a WebRTC fast lane for poses and media |
| `?yield=timeout` | arigl's frame loop on a 0 ms timer instead of requestAnimationFrame (an A/B for pacing) |
| `#token=...` | a private room's token, in the fragment, which the browser never sends to a server |

The page keeps a random device id and key for the browser in localStorage; the relay shows the
device and pins its key.

It needs an `arigl-web` that can run a conference: one whose page reads `url_env` and whose
`arigl.wasm` has the WebSocket transport. Until cvcpkg.org publishes one, `deploy/cyberpcangel`'s
staging refuses older packages ([docs/ROADMAP.md](docs/ROADMAP.md)).

## Contributing

Pull requests run `ci` and `llm-gate`. Commits must not carry AI-assistant attribution (llm-gate
fails them).

## License

MIT ([LICENSE](LICENSE)). libcvc, whose packages run these documents, is LGPL-2.1-only.
