#!/bin/zsh
# run-stack.sh — the 2026-10-24 day pass: every PR's suite in stack order,
# serially, cleaning each worktree's .dd and erasing the Duo sim between PRs.
# Each line: <worktree> <tag> <SIMS> [tourfile] [pre-step]
set -u
S=${0:A:h}; W=${S:h:h}
LOG=$S/results/run-stack.log; mkdir -p $S/results
log() { echo "[$(date +%H:%M:%S)] $*" | tee -a $LOG; }
DUO=$(xcrun simctl list devices | awk -F'[()]' '/iPhone Duo/{print $2; exit}')

step() {
  local wt=$1 tag=$2 sims=$3 tour=${4:-}
  log "== $tag ($wt) sims=$sims tour=${tour:-none}"
  SIMS=${sims//+/ } $S/verify.sh $W/$wt $tag ${tour:+$S/tours/$tour} > /dev/null 2>&1
  log "$(grep -E 'build rc|test .* rc=|UI:|tour .* rc=|ABORT' $S/results/$tag/verify.log | tr '\n' ' ')"
  rm -rf $W/$wt/.dd
  xcrun simctl shutdown all 2>/dev/null; xcrun simctl erase $DUO 2>/dev/null
  log "disk free $(df -g / | awk 'NR==2{print $4}')G"
}

for line in "${(@f)$(cat $S/stack.txt)}"; do
  [[ -z $line || $line == \#* ]] && continue
  args=(${=line})
  if [[ ${args[1]} == merge-pr1 ]]; then
    wt=$W/${args[2]}; F=GolfCaddie.xcodeproj/project.pbxproj
    git -C $wt merge --no-commit --no-ff -q feat/duo-v2-layout-foundations >/dev/null 2>&1
    if git -C $wt diff --name-only --diff-filter=U | grep -q pbxproj; then
      # both sides only add files: keep both
      git -C $wt show :1:$F > $S/results/.b; git -C $wt show :2:$F > $S/results/.o; git -C $wt show :3:$F > $S/results/.t
      git merge-file --union -p $S/results/.o $S/results/.b $S/results/.t > $wt/$F
    fi
    log "merged PR 1 into ${args[2]} (uncommitted, shots only; conflicts: $(git -C $wt diff --name-only --diff-filter=U | tr '\n' ' '))"
  elif [[ ${args[1]} == unmerge ]]; then
    git -C $W/${args[2]} merge --abort && log "aborted the temporary merge in ${args[2]}"
  else
    step ${args[@]}
  fi
done
log "stack done"
