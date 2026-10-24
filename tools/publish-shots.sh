#!/bin/zsh
# publish-shots.sh <tag> <mockup-map-file>
# Copies results/<tag>/shots-duo/*.png as 720px JPEGs to the duo-v2-screenshots
# branch under <tag>/, pushes, and prints a markdown table (shot | mockup | image).
# mockup-map lines: shot-name<TAB>canvas board name
set -eu
S=${0:A:h}; TAG=$1; MAP=${2:+${2:A}}
RES=${RESULTS:-$S/results}; SRC=$RES/$TAG/shots-duo
WT=${SHOTS_WT:-$(cd ${0:A:h}/.. && pwd)}
mkdir -p $WT/$TAG
for f in $RES/$TAG/shots-*/*.png; do
  sips -s format jpeg -s formatOptions 70 -Z 720 $f --out $WT/$TAG/${f:t:r}.jpg >/dev/null
done
cd $WT
git add $TAG >/dev/null
git commit -qm "screenshots: $TAG" >/dev/null 2>&1 || true
git push -q origin duo-v2-screenshots >/dev/null 2>&1
BASE=https://raw.githubusercontent.com/moisesvargasjr/golf-caddie/duo-v2-screenshots/$TAG
echo "| Pose | Canvas mockup | Screenshot |"
echo "|---|---|---|"
for f in $WT/$TAG/*.jpg; do
  n=${f:t:r}
  m=$( [[ -n $MAP && -f $MAP ]] && awk -F'\t' -v n=$n '$1==n{print $2}' $MAP || true)
  echo "| $n | ${m:--} | <img src=\"$BASE/$n.jpg\" width=\"280\"> |"
done
