# The room's relay

cyprty's room is served by libcvc's `arisrv` on **paladin** (an instance on catx-00), listening on:

| port | what |
|---|---|
| 7700 | gRPC state (native clients) |
| 7701 | gRPC media |
| 7702 | WebSocket (browsers); https://cyberpcangel.com/cyprty-ws tunnels here |

It runs the room `standup`, with `CVC_ARISRV_ROOM_DEBUG=1` (a per-participant line every ~5 s in
`/home/tfx/ariadne/relay-<bundle>.log`).

The relay is libcvc's `arisrv` package. On catx-03, under its ramdisk, `build-relay.sh` runs
`cvcpkg install arisrv` for a libcvc release, with that release's libcvc, and makes the install
into a self-contained bundle: `bin/arisrv`, the libraries it loads in `lib/`, and `BUILT-FROM`
(the arisrv and libcvc package versions). `deploy-relay.sh` places the bundle on paladin:

```bash
ssh catx-03 'bash -s' -- 3.7.10 relay-3.7.10 < deploy/relay/build-relay.sh
bash deploy/relay/deploy-relay.sh relay-3.7.10
bash deploy/relay/deploy-relay.sh status
```

The bundle carries libcvc's libraries itself, so paladin needs no cvcpkg. `build-relay.sh` stops if
arisrv's RUNPATH isn't `$ORIGIN/../lib`, if `ldd` finds a library missing, or if arisrv and libcvc
come from different releases.

`deploy-relay.sh` stops the running arisrv and starts the new bundle on the same ports. Earlier
bundles stay in `/home/tfx/ariadne/`, so going back is `deploy-relay.sh <the previous name>`.
A browser client and the relay must come from compatible libcvc trees: deploy the relay before a
page that needs it.
