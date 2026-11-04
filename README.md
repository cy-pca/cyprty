# cyprty

cyprty is a conference room you walk around in: an avatar for everyone, live camera and
microphone, written as [Ariadne](https://github.com/transfix/libcvc/blob/master/docs/ARIADNE.md)
documents. It runs live at **https://cyberpcangel.com/cyprty/**, and natively, without a
browser, in libcvc's `arigl` on Linux and Windows. Browser and native clients share one room.

This repository holds only cyprty's documents and how they are deployed. Everything else comes
from [libcvc](https://github.com/transfix/libcvc), through its published packages:

| | from |
|---|---|
| the documents (`share/cyprty/`) | this repository |
| the browser host (`index.html`, `arigl.wasm`, ...) | libcvc's `arigl-web` package on cvcpkg.org: the stock page, not a build of libcvc |
| the native host | libcvc's `arigl` package on cvcpkg.org |
| the conference itself: rooms, relays, holons, avatar physics, camera and microphone streams | libcvc (cvc::ariadne, cvc::state, cvcGL), in those packages |
| the relay and the room's holon | libcvc's `arisrv` package on cvcpkg.org |

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

It needs `arigl-web` 3.7.9 or later. `main.ari` asks for that version (`min_libcvc: 3.7.9`), and
`deploy/cyberpcangel`'s staging refuses a package whose page can't run a conference.

## Running it natively

The same documents run outside the browser in `arigl`, libcvc's native host (Linux x86_64 and
arm64, Windows). It captures your camera and microphone itself and joins the same room as the
browser clients:

```bash
cvcpkg install arigl --prefix ./deps --config release --link shared
CVC_ARIADNE_RELAY=grpc://paladin.sublevels.net:7700 CVC_ARIADNE_NAME=Alice \
  ./deps/bin/arigl run share/cyprty/main.ari
```

On Windows, in PowerShell:

```powershell
cvcpkg install arigl --prefix .\deps --config release --link shared
$env:CVC_ARIADNE_RELAY = "grpc://paladin.sublevels.net:7700"; $env:CVC_ARIADNE_NAME = "Alice"
.\deps\bin\arigl.exe run share\cyprty\main.ari
```

A native client has no page config. The environment does what the page's link does:

| variable | does | in the browser |
|---|---|---|
| `CVC_ARIADNE_RELAY` | the relay: `grpc://host:7700` (gRPC) or `ws://host:7702` (WebSocket). Unset, the document runs alone, in no room | `?relay=` |
| `CVC_ARIADNE_NAME` | your name in the room (otherwise `guest`) | `?name=` |
| `CVC_ARIADNE_ROOM` | the room to join (otherwise `standup`, the room cyprty's relay serves) | |
| `CVC_ARIADNE_ROOM_TOKEN` | a private room's token | `#token=` |
| `CVC_ARIADNE_SYNTHETIC_CAM=1` | a test pattern instead of your camera | `?synthetic=1` |
| `CVC_ARIGL_LOOK=mouse` or `drag` | start in mouse look or drag to look | `?look=` |

A native client dials the relay's own ports on paladin, not the page's
`wss://cyberpcangel.com/cyprty-ws`: arigl's room transport has no TLS for WebSockets yet, so it
takes `grpc://` (or plain `ws://`) only.

## Running your own room: arisrv

`arisrv` is libcvc's headless conference server. Clients connect only to it, never to each other,
so a room works across home NATs. It serves the room in two roles:

- **The relay.** It forwards the room tree (who is in the room, their streams, chat) and the
  camera and microphone frames between clients:
  - each viewer gets what its link and its place in the room call for;
  - it seeds the room's scene and avatar catalog;
  - it keeps the chat history (in memory).
- **The room's holon.** It holds the server-authoritative copy of the room's world:
  - every avatar is a Jolt rigid body, moving under an energy budget the relay sets for everyone;
  - clients send their intents, and the holon sends back the poses everyone sees.

It needs no GPU or display: core libcvc with gRPC, WebSocket and Jolt, and no cvcGL or VTK.
It is packaged for Linux (x86_64 and arm64), macOS and Windows, from libcvc 3.7.10 on.
`cvcpkg install arisrv` brings libcvc and everything it needs along:

```bash
cvcpkg install arisrv --prefix ./relay --config release --link shared
CVC_ARISRV_ROOM_DEBUG=1 ./relay/bin/arisrv --room standup \
  --state-listen 0.0.0.0:7700 --media-listen 0.0.0.0:7701 --ws-listen 0.0.0.0:7702
```

arisrv runs on the libcvc of its own release. A plain install takes the newest of both. To pin
an older release, name both: `cvcpkg install arisrv==3.7.10 libcvc==3.7.10 ...`.

Those are also its default ports:

| port | for |
|---|---|
| 7700 | gRPC state: native clients (`grpc://`) |
| 7701 | gRPC media streams |
| 7702 | WebSocket: browsers, and native clients on `ws://` |

`CVC_ARISRV_ROOM_DEBUG=1` logs a line per participant every ~5 s. Point the clients at it:

- **A browser**, on the page served as above: `http://localhost:8080/?relay=ws://127.0.0.1:7702`.
- **A native client:**

  ```bash
  CVC_ARIADNE_RELAY=grpc://127.0.0.1:7700 ./deps/bin/arigl run share/cyprty/main.ari
  ```

A browser served from a public host needs the relay behind its TLS (`wss://`). The page dials
`{ws_origin}/cyprty-ws` by default, and on cyberpcangel.com Apache tunnels that path to port 7702
([deploy/cyberpcangel/README.md](deploy/cyberpcangel/README.md)).

The flags most rooms need (`src/arisrv/main.cpp` in libcvc documents every one):

| flag | does |
|---|---|
| `--room NAME` | the room it serves (default `standup`); clients choose it with `CVC_ARIADNE_ROOM` |
| `--room-token-file PATH` | a private room: only clients with the token on PATH's first line get in (or set `CVC_ARISRV_ROOM_TOKEN`). Browsers pass it as `#token=`, native clients as `CVC_ARIADNE_ROOM_TOKEN` |
| `--device-pins PATH` | keep the device-key pins across restarts (otherwise they last one run) |
| `--scene default` or `large` | the seeded scene (`large`: a 100 m plane) |
| `--avatar-energy on` or `off` | the avatars' energy budget (default on) |
| `--video-max RUNG`, `--viewer-kbps-max N` | cap what video each viewer gets |
| `--set KEY=VALUE` | write a state key once the room is up, before anyone joins (a `conf.*` key reaches every client) |

For a Linux server with no cvcpkg, `deploy/relay/build-relay.sh` makes the package into a
self-contained bundle: `bin/arisrv`, the libraries it loads in `lib/`, and `BUILT-FROM`. Copy the
bundle anywhere and run `bin/arisrv` from it. `WORK` is where the install and the bundle go, and
`CVCPKG` is the cvcpkg to use (default `~/.local/bin/cvcpkg`):

```bash
WORK=/tmp/relay bash deploy/relay/build-relay.sh 3.7.10 relay
```

[deploy/relay/README.md](deploy/relay/README.md) covers how cyprty's own room is built and run on
paladin.

## Contributing

Pull requests run `ci` and `llm-gate`. Commits must not carry AI-assistant attribution (llm-gate
fails them).

## License

MIT ([LICENSE](LICENSE)). libcvc, whose packages run these documents, is LGPL-2.1-only.
