#!/bin/zsh
# verify.sh <worktree> <tag> [tourfile]
# Serial: build-for-testing once, test on Duo then 17 Pro, then the screenshot tour on each.
# Never run two at once (resource-capped Mac). Results -> $OUT/<tag>/
set -u
WT=$1; TAG=$2; TOURFILE=${3:-}
S=${0:A:h}; OUT=${RESULTS:-$S/results}/$TAG; mkdir -p $OUT
DD=$WT/.dd
log() { echo "[$(date +%H:%M:%S)] $*" | tee -a $OUT/verify.log; }

free_gb=$(df -g / | awk 'NR==2{print $4}')
log "disk free ${free_gb}G"
if (( free_gb < 10 )); then log "ABORT: disk below 10G"; exit 3; fi

RT=com.apple.CoreSimulator.SimRuntime.iOS-27-1
dev() { xcrun simctl list devices -j | /usr/bin/python3 -I -c "import json,sys;d=json.load(sys.stdin)['devices'].get('$RT',[]);print(next((x['udid'] for x in d if x['name']=='$1'),''))"; }
DUO=$(dev "iPhone Duo"); [[ -z $DUO ]] && DUO=$(xcrun simctl create "iPhone Duo" com.apple.CoreSimulator.SimDeviceType.iPhone-Duo $RT)
# iOS 27.1 accepts only the Duo; take an iPhone 17 Pro from any iOS runtime, else create one on the newest runtime that accepts it.
anydev() { xcrun simctl list devices -j | /usr/bin/python3 -I -c "import json,sys;d=json.load(sys.stdin)['devices'];print(next((x['udid'] for r,l in sorted(d.items(),reverse=True) if '.iOS-' in r for x in l if x['name']=='$1' and x.get('isAvailable',True)),''))"; }
PRO=$(anydev "iPhone 17 Pro")
if [[ -z $PRO ]]; then
  for prt in $(xcrun simctl list runtimes -j | /usr/bin/python3 -I -c "import json,sys;print(' '.join(sorted((r['identifier'] for r in json.load(sys.stdin)['runtimes'] if r['identifier'].split('.')[-1].startswith('iOS-') and r.get('isAvailable')),reverse=True)))"); do
    PRO=$(xcrun simctl create "iPhone 17 Pro" com.apple.CoreSimulator.SimDeviceType.iPhone-17-Pro $prt 2>/dev/null) && break
  done
fi
log "duo=$DUO pro=$PRO"

cd $WT
if [[ -z ${TOUR_ONLY:-} ]]; then
log "build-for-testing"
xcodebuild build-for-testing -project GolfCaddie.xcodeproj -scheme GolfCaddie \
  -destination "platform=iOS Simulator,id=$DUO" -derivedDataPath $DD \
  CODE_SIGNING_ALLOWED=NO > $OUT/build.log 2>&1
rc=$?; log "build rc=$rc"
if (( rc != 0 )); then grep -E "error:" $OUT/build.log | sort -u | head -40 | tee -a $OUT/verify.log; exit 1; fi

PAIRS=("duo:$DUO"); [[ $PRO == [0-9A-F]* ]] && PAIRS+=("pro:$PRO") || log "iPhone 17 Pro: BLOCKED (no compatible runtime installed; only iOS 27.1, which supports iPhone Duo only)"
for pair in $PAIRS; do
  name=${pair%%:*}; id=${pair#*:}
  rm -rf $OUT/test-$name.xcresult
  log "test $name"
  xcodebuild test-without-building -project GolfCaddie.xcodeproj -scheme GolfCaddie \
    -destination "platform=iOS Simulator,id=$id" -derivedDataPath $DD \
    -skip-testing:GolfCaddieUITests/ScreenshotTourUITests \
    -resultBundlePath $OUT/test-$name.xcresult > $OUT/test-$name.log 2>&1
  log "test $name rc=$?  $(grep -E 'Executed [0-9]+ tests' $OUT/test-$name.log | tail -1)"
  grep -E "error: -\[|failed \(" $OUT/test-$name.log | head -30 | tee -a $OUT/verify.log
  xcrun simctl shutdown $id 2>/dev/null
done

fi # TOUR_ONLY

if [[ -n $TOURFILE && -f $TOURFILE ]]; then
  # tourfile lines: device<TAB>shot spec (name|orientation|args)
  # first column = group; each group runs from a clean install on the Duo
  for name in $(cut -f1 $TOURFILE | awk '!seen[$0]++'); do
    id=$DUO
    xcrun simctl boot $id 2>/dev/null; xcrun simctl bootstatus $id -b >/dev/null 2>&1
    # The Vineyard at Escondido, hole 1 fairway (tee 33.0716,-117.053691 → green 33.069494,-117.056016)
    xcrun simctl uninstall $id com.moisesvargasjr.golfcaddie >/dev/null 2>&1
    xcrun simctl location $id set 33.0707,-117.0548 >/dev/null 2>&1
    xcrun simctl privacy $id grant location com.moisesvargasjr.golfcaddie >/dev/null 2>&1
    tour=$(awk -F'\t' -v d=$name '$1==d{print $2}' $TOURFILE | paste -sd';' -)
    [[ -z $tour ]] && continue
    rm -rf $OUT/tour-$name.xcresult
    log "tour $name"
    TEST_RUNNER_TOUR="$tour" xcodebuild test-without-building -project GolfCaddie.xcodeproj -scheme GolfCaddie \
      -destination "platform=iOS Simulator,id=$id" -derivedDataPath $DD \
      -only-testing:GolfCaddieUITests/ScreenshotTourUITests \
      -resultBundlePath $OUT/tour-$name.xcresult > $OUT/tour-$name.log 2>&1
    log "tour $name rc=$?"
    rm -rf $OUT/shots-$name; mkdir -p $OUT/shots-$name
    xcrun xcresulttool export attachments --path $OUT/tour-$name.xcresult --output-path $OUT/shots-$name >/dev/null 2>&1
    # rename exported files to their attachment names using the manifest
    if [[ -f $OUT/shots-$name/manifest.json ]]; then
      /usr/bin/python3 -I - $OUT/shots-$name <<'PY'
import json,os,sys
d=sys.argv[1]
for t in json.load(open(os.path.join(d,'manifest.json'))):
    for a in t.get('attachments',[]):
        src=os.path.join(d,a['exportedFileName']); nm=a.get('suggestedHumanReadableName','')
        base=nm.split('_')[0] if nm else a['exportedFileName']
        if os.path.exists(src): os.rename(src,os.path.join(d,base+'.png'))
PY
    fi
    xcrun simctl shutdown $id 2>/dev/null
    log "shots: $(ls $OUT/shots-$name | grep png | tr '\n' ' ')"
  done
fi
log "done"
