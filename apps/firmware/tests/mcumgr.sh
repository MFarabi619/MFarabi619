#!/usr/bin/env bash

HOSTNAME=xiao.local
HOST=$(ping $HOSTNAME -c1 | head -1 | awk -F'[()]' 'NR==1{print $2}')
[ -z "$HOST" ] && {
  echo "couldn't resolve $HOSTNAME" >&2
  exit 1
}

mcumgrctl --udp "$HOST"
mcumgrctl --udp "$HOST" os echo hello
mcumgrctl --udp "$HOST" shell "net iface"
mcumgrctl --udp "$HOST" os task-statistics --json | jq
# mcumgrctl --udp 10.0.0.21 os memory-pool-statistics --json | jq
# mcumgrctl --udp $HOST os get-datetime --json | jq
mcumgrctl --udp "$HOST" os mcumgr-parameters --json | jq
mcumgrctl --udp "$HOST" os application-info --json | jq
mcumgrctl --udp "$HOST" os bootloader-info --json | jq

mcumgrctl --udp "$HOST" image get-state --json | jq
mcumgrctl --udp "$HOST" image slot-info --json | jq

# mcumgrctl --udp $HOST firmware get-image-info --json | jq

# mcumgrctl --udp $HOST firmware update build/firmware/zephyr/zephyr.signed.bin
mcumgrctl --udp "$HOST" image set-state --confirm --json | jq

mcumgrctl --udp "$HOST" enum list-groups --json | jq
mcumgrctl --udp "$HOST" enum show-group-details --json | jq
