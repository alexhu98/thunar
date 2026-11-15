#!/bin/bash
# Issue #126: tabs opened together with -t/-T sort by the saved sort (here Name ascending), not by the hidden Date Created.
set -euo pipefail
. .github/scripts/verify-lib.sh

W=1000
H=700
LEFT=$((W / 4))
RIGHT=$((W * 3 / 4))
DIRS=(alpha beta gamma delta epsilon zeta)

for d in "${DIRS[@]}"; do mkdir -p "$WORK/$d"; done
for f in z m a; do
  for d in "${DIRS[@]}"; do echo "$f" > "$WORK/$d/$f.txt"; done
  sleep 1.1
done
ZB=$(stat -c %W "$WORK/alpha/z.txt")
AB=$(stat -c %W "$WORK/alpha/a.txt")
(( ZB > 0 && ZB < AB )) || fail "the filesystem under $WORK records no distinct birth times, so Date Created would sort like Name"

xfconf-query -c thunar -p /default-view -n -t string -s ThunarDetailsView
xfconf-query -c thunar -p /last-sort-column -n -t string -s THUNAR_COLUMN_NAME
xfconf-query -c thunar -p /last-sort-order -n -t string -s GTK_SORT_ASCENDING

pane_click() {  # x
  focus "$MAIN"
  xdotool mousemove --window "$MAIN" "$1" $((H - 80))
  sleep 0.2
  xdotool click 1
  sleep 0.5
}

next_tab() {  # x expected-title
  pane_click "$1"
  xdotool key ctrl+Page_Down
  wait_title "$MAIN" "$2"
  sleep 0.5
}

N=0
first_is_a() {  # x folder
  local dest got i
  N=$((N + 1))
  dest="$WORK/check-$N"
  mkdir -p "$dest"
  pane_click "$1"
  wait_title "$MAIN" "$2"
  xdotool key Home
  sleep 0.3
  xdotool key ctrl+c
  sleep 0.3
  open_thunar "$dest"
  wait_title "$WID" "check-$N"
  focus "$WID"
  xdotool key ctrl+v
  for ((i = 0; i < 25; i++)); do
    got=$(ls -A "$dest" | tr '\n' ' ')
    [[ -n $got ]] && break
    sleep 0.2
  done
  xdotool key ctrl+w
  sleep 0.5
  WID=$MAIN
  [[ $got == "a.txt " ]] || fail "$2: the first row is '$got', expected 'a.txt ' (Name ascending; z.txt first means Date Created)"
}

open_thunar --split=50 -t "$WORK/alpha" "$WORK/beta" "$WORK/gamma" -T "$WORK/delta" "$WORK/epsilon" "$WORK/zeta"
MAIN=$WID
xdotool windowsize --sync "$MAIN" "$W" "$H"
wait_title "$MAIN" alpha
sleep 1

first_is_a "$LEFT" alpha
next_tab "$LEFT" beta
first_is_a "$LEFT" beta
next_tab "$LEFT" gamma
first_is_a "$LEFT" gamma
shot "$MAIN" left-last-tab "Left pane on its third tab, gamma: a.txt, m.txt, z.txt in name order, and the Name header shows the sort arrow"

first_is_a "$RIGHT" delta
next_tab "$RIGHT" epsilon
first_is_a "$RIGHT" epsilon
next_tab "$RIGHT" zeta
first_is_a "$RIGHT" zeta
shot "$MAIN" right-last-tab "Right pane on its third tab, zeta: a.txt, m.txt, z.txt in name order, and the Name header shows the sort arrow"
