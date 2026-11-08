#!/bin/bash
# Issue #19: drop files on a tab label to move them into that tab's folder.
# Issue #24: double-click on a pane's tab bar to open the parent folder, and the two new Preferences checkboxes.
set -euo pipefail
. .github/scripts/verify-lib.sh

W=1000
H=700
TOP=$(basename "$WORK")

xfconf-query -c thunar -p /misc-double-click-blank-go-up -n -t bool -s false
mkdir -p "$WORK/alpha" "$WORK/beta"
echo "moved by a drop on a tab" > "$WORK/alpha/moved.txt"

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

park() { xdotool mousemove --window "$WID" $((W / 2)) $((H - 10)); }

click_at() {  # x y
  xdotool mousemove --window "$WID" "$1" "$2"
  sleep 0.2
  xdotool click 1
  park
}

double_at() {  # x y
  focus "$WID"
  xdotool mousemove --window "$WID" "$1" "$2"
  sleep 0.3
  xdotool click --repeat 2 --delay 80 1
  park
}

open_prefs() {
  thunar-settings &
  PREFS=''
  for ((i = 0; i < 50; i++)); do
    PREFS=$(xdotool search --onlyvisible --name "Thunar Preferences" 2>/dev/null | head -1) && [[ -n $PREFS ]] && break
    sleep 0.2
  done
  [[ -n $PREFS ]] || fail "the Preferences dialog did not open"
  focus "$PREFS"
  xdotool key ctrl+Page_Down
  sleep 0.3
  xdotool key ctrl+Page_Down
  sleep 0.5
}

D='Drop files on a tab label (#19)'
T='Double-click a tab to go up (#24)'
P='Preferences checkboxes (#24)'

open_thunar "$WORK/alpha"
xdotool windowsize --sync "$WID" "$W" "$H"
wait_start alpha
focus "$WID"
xdotool key ctrl+2
sleep 0.5
xdotool key F9
sleep 0.5
xdotool key ctrl+t
sleep 0.5
xdotool key ctrl+l
sleep 0.3
xdotool type --delay 5 "$WORK/beta"
xdotool key Return
wait_start beta
xdotool key Escape ctrl+Page_Up
wait_start alpha
sleep 0.5

# Find the tab row: click upward from the middle of the window at 3/4 of the width until beta's tab is hit
TY=''
for ((y = H / 2; y > 40; y -= 6)); do
  click_at $((W * 3 / 4)) "$y"
  sleep 0.3
  if starts beta; then TY=$((y - 6)); break; fi
done
[[ -n $TY ]] || fail "could not find the tab bar"
BX=$((W * 3 / 4))
AX=''
for ((x = 30; x < W / 2; x += 30)); do
  click_at "$x" "$TY"
  sleep 0.3
  if starts alpha; then AX=$x; break; fi
done
[[ -n $AX ]] || fail "could not find alpha's tab"
echo "tab row y=$TY, alpha tab x=$AX, beta tab x=$BX"

# 19: drag moved.txt from alpha's view onto beta's tab label
shot "$WID" before-tab-drop "Two tabs, alpha (current, details view, showing moved.txt) and beta; beta's folder is empty"
dropped=''
for ((ry = TY + 20; ry < TY + 120; ry += 6)); do
  focus "$WID"
  xdotool mousemove --window "$WID" 150 "$ry"
  sleep 0.3
  xdotool mousedown 1
  for ((s = 1; s <= 10; s++)); do
    xdotool mousemove --window "$WID" $((150 + (BX - 150) * s / 10)) $((ry + (TY - ry) * s / 10))
    sleep 0.08
  done
  sleep 0.3
  xdotool mouseup 1
  park
  sleep 1.5
  if [[ -e $WORK/beta/moved.txt ]]; then dropped=$ry; break; fi
  click_at "$AX" "$TY"
  wait_start alpha
done
[[ -n $dropped ]] || fail "dropping moved.txt on beta's tab never moved it into beta"
[[ ! -e $WORK/alpha/moved.txt ]] || fail "moved.txt is still in alpha after the drop: it was copied, not moved"
[[ $(cat "$WORK/beta/moved.txt") == "moved by a drop on a tab" ]] || fail "moved.txt changed on the way"
click_at "$BX" "$TY"
wait_start beta
sleep 0.5
shot "$WID" after-tab-drop "The beta tab now shows moved.txt, which the drop on its label moved out of alpha (the script asserts alpha no longer has it)"
pair tab-drop "Dragged moved.txt from alpha's file list and dropped it on beta's tab label" "A drop on a tab label moves the files into that tab's folder" "alpha has moved.txt, beta empty" "beta has moved.txt, alpha has none" "$D"

# 24: a double-click on a tab that isn't current switches to it and takes it up
click_at "$AX" "$TY"
wait_start alpha
sleep 0.5
shot "$WID" before-tab-up "Two tabs, alpha (current) and beta; the window shows alpha"
double_at "$BX" "$TY"
wait_start "$TOP"
shot "$WID" after-tab-up "A double-click on beta's tab switched to it and took it up to $TOP, the parent folder (it shows alpha and beta)"
pair tab-up "Double-clicked the label of the beta tab while alpha was current" "A double-click on a tab that isn't current switches to it and opens its parent folder" "alpha current, beta tab" "that tab now on $TOP, the parent" "$T"
click_at "$AX" "$TY"
wait_start alpha

# 24: split view, with always-show-tabs turned on in Preferences
xdotool key F3
sleep 1
click_at $((W * 3 / 4)) $((H - 80))
sleep 0.5
starts alpha || fail "the new right pane is on '$(title)', expected alpha"
shot "$WID" before-always-tabs "Split view: the left pane has two tabs and a tab bar; the right pane has one tab and no tab bar"
open_prefs
shot "$PREFS" before-pref-always "Preferences, Behavior tab, Tabs and Windows: Always show tabs, even with only one open is unticked"
xdotool key alt+a
sleep 0.5
[[ $(xfconf-query -c thunar -p /misc-always-show-tabs) == true ]] || fail "ticking Always show tabs did not store true in xfconf"
shot "$PREFS" after-pref-always "After Alt+A, Always show tabs, even with only one open is ticked (the script asserts xfconf reads true)"
pair pref-always "Pressed Alt+A, the new checkbox's mnemonic" "The Always show tabs checkbox stores the hidden setting in xfconf" "Always show tabs unticked" "ticked, xfconf true" "$P"
xdotool key Escape
sleep 0.5
focus "$WID"
sleep 0.5
shot "$WID" after-always-tabs "The right pane, with its one tab, now has a tab bar too, shown at once without a restart"
pair always-tabs "Ticked Always show tabs in Preferences and closed the dialog" "Always show tabs shows a single-tab pane's tab bar at once" "right pane: one tab, no tab bar" "right pane: tab bar shown" "$P"

RX=$((W * 3 / 4 - 60))
click_at "$RX" $((H - 80))
sleep 0.5
shot "$WID" before-split-right "Split view, the right pane active: both panes on alpha, each with a tab bar"
double_at "$RX" "$TY"
wait_start "$TOP"
shot "$WID" after-split-right "A double-click on the right pane's tab took only the right pane up to $TOP; the left pane still shows alpha"
click_at $((W / 4)) $((H - 80))
wait_start alpha
pair split-right "Double-clicked the right pane's only tab" "In split view only the pane whose tab was double-clicked goes up" "both panes on alpha" "right pane on $TOP, left on alpha" "$T"

# 24: unticking the checkbox turns it off at once
open_prefs
shot "$PREFS" before-pref-off "Preferences, Behavior tab: Double-click on a tab to open the parent folder is ticked"
xdotool key alt+t
sleep 0.5
[[ $(xfconf-query -c thunar -p /misc-double-click-tab-go-up) == false ]] || fail "unticking the checkbox did not store false in xfconf"
shot "$PREFS" after-pref-off "After Alt+T, Double-click on a tab to open the parent folder is unticked (the script asserts xfconf reads false)"
pair pref-off "Pressed Alt+T, the new checkbox's mnemonic" "The new checkbox turns the tab double-click off and stores false" "checkbox ticked" "checkbox unticked, xfconf false" "$P"
xdotool key Escape
sleep 0.5

focus "$WID"
shot "$WID" before-off "Setting off: split view, the left pane active on alpha"
double_at "$AX" "$TY"
sleep 2
starts alpha || fail "with the setting off, a double-click on a tab went to '$(title)'"
shot "$WID" after-off "With the setting off, a double-click on alpha's tab left the left pane on alpha"
pair off "Double-clicked alpha's tab in the left pane and waited 2 s" "With the setting off, a double-click on a tab does nothing" "setting off, left pane on alpha" "still on alpha" "$P"
