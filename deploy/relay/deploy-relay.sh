#!/usr/bin/env bash
# deploy-relay.sh: place a relay bundle (build-relay.sh) on paladin and swap the running relay to it.
#
#   deploy/relay/deploy-relay.sh NAME        run from a machine that can ssh to catx-03 and catx-00
#   deploy/relay/deploy-relay.sh status      what is running now, and its log's first lines
#
# The bundle goes catx-03:$WORK/NAME -> paladin:/home/tfx/ariadne/NAME; earlier bundles stay where
# they are, so going back is `deploy-relay.sh <the previous NAME>`. The relay listens on 7700 (gRPC
# state), 7701 (gRPC media) and 7702 (WebSocket, which cyberpcangel.com/cyprty-ws tunnels to).
set -euo pipefail
HOST=${HOST:-tfx@catx-00.tx.wtf}
WORK=${WORK:-/mnt/ramdisk/tfx/cyprty-relay}
ROOM=${ROOM:-standup}
in_paladin() { ssh -o BatchMode=yes "$HOST" "lxc exec paladin --project catx -- bash -s"; }

case "${1:-}" in
"" ) echo "usage: $0 NAME|status" >&2; exit 2 ;;
status)
  in_paladin <<'EOS'
pgrep -x arisrv -a || echo "no arisrv running"
for p in $(pgrep -x arisrv); do
  b=$(readlink -f /proc/$p/cwd); echo "bundle: $b"; cat "$b/BUILT-FROM" 2>/dev/null || true
done
EOS
  ;;
*)
  NAME=$1
  [[ "$NAME" =~ ^[A-Za-z0-9._-]+$ ]] || { echo "bad bundle name: $NAME" >&2; exit 2; }
  echo "=== copy the bundle catx-03 -> paladin ==="
  ssh -o BatchMode=yes catx-03 "test -x $WORK/$NAME/bin/arisrv && tar czf - -C $WORK $NAME" |
    ssh -o BatchMode=yes "$HOST" "lxc exec paladin --project catx -- bash -c 'mkdir -p /home/tfx/ariadne && rm -rf /home/tfx/ariadne/$NAME && tar xzf - -C /home/tfx/ariadne && chown -R tfx:tfx /home/tfx/ariadne/$NAME'"
  echo "=== swap the running relay (same ports) ==="
  { echo "B=/home/tfx/ariadne/$NAME ROOM=$ROOM"; cat <<'EOS'
set -e
cat $B/BUILT-FROM
ldd $B/bin/arisrv | grep "not found" && { echo "FATAL: unresolved libraries"; exit 1; } || true
for p in $(pgrep -x arisrv); do echo "stopping $p: $(tr '\0' ' ' < /proc/$p/cmdline)"; kill $p; done
sleep 2
cd $B
sudo -u tfx setsid nohup env CVC_ARISRV_ROOM_DEBUG=1 ./bin/arisrv --room $ROOM \
  --state-listen 0.0.0.0:7700 --media-listen 0.0.0.0:7701 --ws-listen 0.0.0.0:7702 \
  > /home/tfx/ariadne/relay-${B##*/}.log 2>&1 < /dev/null &
sleep 3
pgrep -x arisrv -a
head -5 /home/tfx/ariadne/relay-${B##*/}.log
EOS
  } | in_paladin
  ;;
esac
