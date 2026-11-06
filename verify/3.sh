#!/bin/bash
# Issue #3: a double-click on blank space opens the parent folder.
set -euo pipefail
. .github/scripts/verify-lib.sh

W=1000
H=700
ITEM_X=239
ITEM_Y=130

mkdir -p "$WORK/alpha/bravo/charlie/delta"
for f in one two three; do echo "$f" > "$WORK/alpha/bravo/charlie/$f.txt"; done
echo note > "$WORK/alpha/bravo/charlie/delta/inside.txt"

blank_double_click() {  # x y, relative to the window
  focus "$WID"
  xdotool mousemove --window "$WID" "$1" "$2"
  sleep 1
  xdotool click --repeat 2 --delay 80 1
}

reopen() {  # path, view key (1 icon, 2 details, 3 compact), expected title
  xdotool key ctrl+l
  sleep 0.3
  xdotool type --delay 5 "$1"
  xdotool key Return
  wait_title "$WID" "${3:-$(basename "$1")}"
  xdotool key Escape "ctrl+$2"
  sleep 0.5
}

title() { xdotool getwindowname "$WID"; }

open_thunar "$WORK/alpha/bravo/charlie"
xdotool windowsize --sync "$WID" "$W" "$H"
wait_title "$WID" charlie
focus "$WID"

# Icon view
xdotool key ctrl+1
sleep 0.5
shot "$WID" before-icon "Icon view shows folder charlie (delta, one.txt, two.txt, three.txt), with the path bar ending in charlie"
blank_double_click $((W - 120)) $((H - 120))
wait_title "$WID" bravo
shot "$WID" after-icon "Icon view now shows folder bravo, the parent of charlie, after a double-click on blank space"

# Compact view
reopen "$WORK/alpha/bravo/charlie" 3
shot "$WID" before-compact "Compact view shows folder charlie, with the path bar ending in charlie"
blank_double_click $((W - 120)) $((H - 120))
wait_title "$WID" bravo
shot "$WID" after-compact "Compact view now shows folder bravo, the parent of charlie, after a double-click on blank space"

# Details view
reopen "$WORK/alpha/bravo/charlie" 2
shot "$WID" before-details "Details view shows folder charlie as rows, with the path bar ending in charlie"
blank_double_click $((W - 120)) $((H - 120))
wait_title "$WID" bravo
shot "$WID" after-details "Details view now shows folder bravo, the parent of charlie, after a double-click on the blank space below the rows"

# A double-click on a folder still opens that folder
reopen "$WORK/alpha/bravo/charlie" 1
shot "$WID" before-folder "Icon view shows folder charlie with the delta folder as its first item"
focus "$WID"
xdotool mousemove --window "$WID" "$ITEM_X" "$ITEM_Y"
sleep 0.3
xdotool click --repeat 2 --delay 80 1
wait_title "$WID" delta
shot "$WID" after-folder "A double-click on the delta folder opened delta (inside.txt shown), not the parent folder"

# Rubber-band selection still works
reopen "$WORK/alpha/bravo/charlie" 1
focus "$WID"
xdotool mousemove --window "$WID" 300 260
sleep 1
xdotool mousedown 1
for y in 220 180 140 110; do
  xdotool mousemove --window "$WID" 200 "$y"
  sleep 0.1
done
xdotool mouseup 1
sleep 0.5
[[ $(title) == *charlie* ]] || fail "the drag changed the folder to '$(title)'"
shot "$WID" rubber-band "A drag from blank space selected only the delta folder and left the window on charlie"
xdotool key Return
wait_title "$WID" delta

# Split view: each pane goes up on its own
reopen "$WORK/alpha/bravo/charlie" 1
xdotool key F3
sleep 1
focus "$WID"
xdotool mousemove --window "$WID" $((W - 80)) $((H - 120)) click 1
sleep 1
shot "$WID" before-split-right "Split view with both panes on folder charlie, the right pane active"
blank_double_click $((W - 80)) $((H - 120))
wait_title "$WID" bravo
blank_double_click $((W - 80)) $((H - 120))
wait_title "$WID" alpha
shot "$WID" after-split-right "Two double-clicks in the right pane took it up twice to alpha: the active right pane shows folder bravo, alpha's only item"
xdotool mousemove --window "$WID" $((W / 2 - 80)) $((H - 120))
sleep 1
xdotool click 1
wait_title "$WID" charlie
sleep 1
shot "$WID" before-split-left "Split view with the left pane active on folder charlie (delta, one.txt, three.txt, two.txt)"
blank_double_click $((W / 2 - 80)) $((H - 120))
wait_title "$WID" bravo
[[ $(title) != *alpha* ]] || fail "the title is on alpha after the left pane click"
shot "$WID" after-split-left "A double-click in the left pane took only that pane up to bravo (it shows folder charlie)"
xdotool key F3
sleep 0.5

# At / nothing happens
reopen / 1 "File System"
before=$(title)
shot root before-root "The whole screen: Thunar shows the root folder / in icon view and no other window is open"
blank_double_click $((W - 60)) $((H - 60))
sleep 2
[[ $(title) == "$before" ]] || fail "title changed at / from '$before' to '$(title)'"
[[ $(xdotool search --all --onlyvisible --pid "$THUNAR_PID" --class Thunar | wc -l) -eq 1 ]] || fail "a dialog opened at /"
shot root after-root "The whole screen after a double-click on blank space at /: Thunar still shows / and no dialog opened"

# Turned off in Preferences: nothing happens
reopen "$WORK/alpha/bravo/charlie" 1
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
shot "$PREFS" before-pref "Preferences, Behavior tab: the checkbox Double-click on a blank area to open the parent folder is ticked"
xdotool key alt+p
sleep 0.5
[[ $(xfconf-query -c thunar -p /misc-double-click-blank-go-up) == false ]] || fail "unticking the checkbox did not store false in xfconf"
shot "$PREFS" after-pref "After Alt+P the checkbox Double-click on a blank area to open the parent folder is unticked (the script asserts xfconf then reads false)"
xdotool key Escape
sleep 0.5

shot "$WID" before-off "With the checkbox unticked, the same running Thunar shows folder charlie in icon view"
blank_double_click $((W - 120)) $((H - 120))
sleep 2
[[ $(title) == *charlie* ]] || fail "with the setting off, the title changed to '$(title)'"
shot "$WID" after-off "With the setting off, a double-click on blank space left the window on folder charlie"
