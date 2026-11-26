#!/bin/bash
# Issue #155: Ctrl+Page Up / Ctrl+Page Down (and Ctrl+Tab / Ctrl+Shift+Tab) switch tabs across the split boundary,
# in the left pane's tabs then the right pane's, wrapping around at the ends; the new pane becomes active and its
# view gets the keyboard focus. Without split view they still cycle through the one pane's tabs.
set -euo pipefail
. .github/scripts/verify-lib.sh

W=1000
H=700
LEFT=$((W / 4))
G='Previous / Next Tab across the split (#155)'

mkdir -p "$WORK/alpha" "$WORK/bravo" "$WORK/charlie/inside" "$WORK/delta" "$WORK/echo" "$WORK/foxtrot"
echo 1 > "$WORK/alpha/a.txt"
echo 2 > "$WORK/bravo/b.txt"
echo 4 > "$WORK/delta/d.txt"

xfconf-query -c thunar -p /default-view -n -t string -s ThunarDetailsView

title() { xdotool getwindowname "$WID"; }

starts() { [[ $(title) == "$1" || $(title) == "$1 "* ]]; }

wait_start() {  # name
  local i
  for ((i = 0; i < 50; i++)); do
    starts "$1" && return 0
    sleep 0.2
  done
  fail "window title is '$(title)', expected it to start with '$1'"
}

park() { xdotool mousemove --window "$WID" $((W / 2)) 5; }

pane() {  # x expected-title
  xdotool mousemove --window "$WID" "$1" $((H - 80))
  sleep 0.2
  xdotool click 1
  park
  wait_start "$2"
  sleep 0.3
}

press() {  # key expected-title
  xdotool key "$1"
  wait_start "$2"
  sleep 0.5
}

open_thunar --split=50 -t "$WORK/alpha" "$WORK/bravo" -T "$WORK/charlie" "$WORK/delta"
xdotool windowsize --sync "$WID" "$W" "$H"
wait_start alpha
focus "$WID"
sleep 1

pane "$LEFT" alpha
press ctrl+Page_Down bravo
shot "$WID" before-next "Split view: the left pane is active on its last tab, bravo; the right pane shows charlie, its first tab, dimmed as inactive"
press ctrl+Page_Down charlie
shot "$WID" after-next "The right pane is now active on charlie and the left pane, still on bravo, is dimmed (the script asserts the title charlie)"
pair next "On the left pane's last tab, bravo, pressed Ctrl+Page Down" "Next Tab crosses the split: bravo's next tab is the right pane's first, charlie, and that pane becomes active" "left pane active on bravo" "right pane active on charlie" "$G"

press ctrl+Page_Up bravo
shot "$WID" back-to-bravo "Ctrl+Page Up from charlie made the left pane active again on bravo; the right pane is dimmed (the script asserts the title bravo)"

press ctrl+Page_Down charlie
press ctrl+Page_Down delta
shot "$WID" before-wrap-next "The right pane is active on the last tab overall, delta; the left pane shows bravo"
press ctrl+Page_Down alpha
shot "$WID" after-wrap-next "Ctrl+Page Down from delta wrapped to alpha, the left pane's first tab, and the left pane is active (the script asserts the title alpha)"
pair wrap-next "On the last tab overall, delta in the right pane, pressed Ctrl+Page Down" "Next Tab wraps around the combined order, from the right pane's last tab to the left pane's first" "right pane active on delta" "left pane active on alpha" "$G"

press ctrl+Page_Up delta
shot "$WID" wrap-to-delta "Ctrl+Page Up from alpha wrapped back to delta, and the right pane is active (the script asserts the title delta)"

press ctrl+Page_Up charlie
press ctrl+Page_Up bravo
shot "$WID" before-ctrl-tab "The left pane is active on bravo again, its last tab; the right pane shows charlie"
press ctrl+Tab charlie
shot "$WID" after-ctrl-tab "Ctrl+Tab from bravo moved to charlie and made the right pane active (the script asserts the title charlie)"
pair ctrl-tab "On the left pane's last tab, bravo, pressed Ctrl+Tab" "Ctrl+Tab shares Next Tab's behavior and crosses the split too" "left pane active on bravo" "right pane active on charlie" "$G"
press ctrl+shift+ISO_Left_Tab bravo
press ctrl+Page_Down charlie

xdotool key ctrl+a
sleep 0.5
shot "$WID" before-focus "Right after Ctrl+Page Down crossed from bravo to charlie, Ctrl+A selected charlie's only item, the folder inside, in the right pane"
press Return inside
shot "$WID" after-focus "Return opened the folder inside in the right pane, so the keyboard focus was in that pane's view (the script asserts the title inside)"
pair focus "After Ctrl+Page Down crossed to charlie, pressed Ctrl+A, then Return" "After crossing, the keyboard focus is in the new pane's file view, so Return opens its selection" "inside selected in charlie" "right pane opened inside" "$G"

open_thunar -t "$WORK/echo" "$WORK/foxtrot"
xdotool windowsize --sync "$WID" "$W" "$H"
wait_start echo
focus "$WID"
sleep 1
pane $((W / 2)) echo
press ctrl+Page_Down foxtrot
shot "$WID" before-no-split "A window without split view on its last tab, foxtrot; its first tab is echo"
press ctrl+Page_Down echo
shot "$WID" after-no-split "Ctrl+Page Down from foxtrot wrapped to echo, the first tab (the script asserts the title echo)"
pair no-split "Without split view, on the last tab, foxtrot, pressed Ctrl+Page Down" "Without split view Next Tab still cycles through the one pane's tabs, wrapping around" "on foxtrot, the last tab" "on echo, the first tab" "$G"
press ctrl+Page_Up foxtrot
