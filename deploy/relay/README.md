# The room's relay

cyprty's room is served by libcvc's `arisrv` on **paladin** (an instance on catx-00), listening on:

| port | what |
|---|---|
| 7700 | gRPC state (native clients) |
| 7701 | gRPC media |
| 7702 | WebSocket (browsers); https://cyberpcangel.com/cyprty-ws tunnels here |

It runs the room `standup`, with `CVC_ARISRV_ROOM_DEBUG=1` (a per-participant line every ~5 s in
`/home/tfx/ariadne/relay-<bundle>.log`).

arisrv has no cvcpkg package yet, so the relay is built from a libcvc ref on catx-03, under its
ramdisk, into a self-contained bundle (`bin/arisrv`, `lib/`, `BUILT-FROM`), then placed on
paladin:

```bash
ssh catx-03 'bash -s' -- master relay-<short-commit> < deploy/relay/build-relay.sh
bash deploy/relay/deploy-relay.sh relay-<short-commit>
bash deploy/relay/deploy-relay.sh status
```

`deploy-relay.sh` stops the running arisrv and starts the new bundle on the same ports. Earlier
bundles stay in `/home/tfx/ariadne/`, so going back is `deploy-relay.sh <the previous name>`.
A browser client and the relay must come from compatible libcvc trees: deploy the relay before a
page that needs it.
