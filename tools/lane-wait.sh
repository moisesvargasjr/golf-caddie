#!/bin/zsh
# Exits (printing LANE_FREE) when ~/.sim-lane-free exists or the sim lane has been idle 15 min.
STATE=${0:h}/idle-since
while true; do
  if [[ -e ~/.sim-lane-free ]]; then echo "LANE_FREE flag"; exit 0; fi
  busy=0
  pgrep -x xcodebuild >/dev/null && busy=1
  pgrep -x Simulator >/dev/null && busy=1
  [[ $(xcrun simctl list devices booted 2>/dev/null | grep -c Booted) -gt 0 ]] && busy=1
  now=$(date +%s)
  if (( busy )); then rm -f $STATE; else
    [[ -f $STATE ]] || echo $now > $STATE
    if (( now - $(cat $STATE) >= 900 )); then echo "LANE_FREE idle15"; exit 0; fi
  fi
  sleep 120
done
