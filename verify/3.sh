#!/bin/bash
# Issue #3: a double-click on blank space opens the parent folder.
set -euo pipefail
. .github/scripts/verify-lib.sh

W=1000
H=700
ITEM_X=239
ITEM_Y=130
ROW_Y=$((103 + (EUID == 0 ? 34 : 0)))

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

V='Each view goes up on a blank double-click'
I='Double-clicks on items still open them'
P='Split view: each pane on its own'
N='Where nothing should happen'

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
pair icon "Double-clicked the blank space in the lower right of the icon view" "A double-click on blank space in icon view opens the parent folder" "charlie, icon view" "bravo, the parent" "$V"

# Compact view
reopen "$WORK/alpha/bravo/charlie" 3
shot "$WID" before-compact "Compact view shows folder charlie, with the path bar ending in charlie"
blank_double_click $((W - 120)) $((H - 120))
wait_title "$WID" bravo
shot "$WID" after-compact "Compact view now shows folder bravo, the parent of charlie, after a double-click on blank space"
pair compact "Reopened charlie in compact view, then double-clicked the blank space in the lower right" "A double-click on blank space in compact view opens the parent folder" "charlie, compact view" "bravo, the parent" "$V"

# Details view
reopen "$WORK/alpha/bravo/charlie" 2
shot "$WID" before-details "Details view shows folder charlie as rows, with the path bar ending in charlie"
blank_double_click $((W - 120)) $((H - 120))
wait_title "$WID" bravo
shot "$WID" after-details "Details view now shows folder bravo, the parent of charlie, after a double-click on the blank space below the rows"
pair details "Reopened charlie in details view, then double-clicked the blank space below the rows" "A double-click below the rows in details view opens the parent folder" "charlie, details view" "bravo, the parent" "$V"

# A double-click on a folder row in details view opens it and stays there
reopen "$WORK/alpha/bravo/charlie" 2
shot "$WID" before-details-folder "Details view shows folder charlie with delta as its first row"
focus "$WID"
xdotool mousemove --window "$WID" "$ITEM_X" "$ROW_Y"
sleep 1
xdotool click --repeat 2 --delay 80 1
wait_title "$WID" delta
sleep 1.5
[[ $(title) == *delta* ]] || fail "after opening delta in details view the window went on to '$(title)'"
shot "$WID" after-details-folder "A double-click on the delta row opened delta (inside.txt shown) and did not go back up to charlie"
pair details-folder "Double-clicked the delta row in details view, then waited 1.5 s" "A double-click on a folder row opens that folder and does not also go up" "charlie, delta row first" "delta, still there after 1.5 s" "$I"

# A double-click on a folder still opens that folder
reopen "$WORK/alpha/bravo/charlie" 1
shot "$WID" before-folder "Icon view shows folder charlie with the delta folder as its first item"
focus "$WID"
xdotool mousemove --window "$WID" "$ITEM_X" "$ITEM_Y"
sleep 0.3
xdotool click --repeat 2 --delay 80 1
wait_title "$WID" delta
sleep 1.5
[[ $(title) == *delta* ]] || fail "after opening delta the window went on to '$(title)'"
shot "$WID" after-folder "A double-click on the delta folder opened delta (inside.txt shown), not the parent folder"
pair folder "Double-clicked the delta folder icon in icon view, then waited 1.5 s" "A double-click on a folder icon opens that folder, not the parent" "charlie, delta first" "delta, not the parent" "$I"

# Rubber-band selection still works
reopen "$WORK/alpha/bravo/charlie" 1
focus "$WID"
xdotool key ctrl+shift+a
sleep 0.5
shot "$WID" before-rubber-band "Icon view of folder charlie with nothing selected"
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
shot "$WID" after-rubber-band "A drag from blank space selected only the delta folder and left the window on charlie"
pair rubber-band "Cleared the selection, then dragged from blank space up and left over the delta icon" "A drag that starts on blank space still selects, and never goes up" "charlie, nothing selected" "charlie, delta selected" "$I"
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
pair split-right "Double-clicked blank space in the right pane twice" "Each double-click takes only the active right pane up one folder" "both panes on charlie, right active" "right pane up twice, on alpha" "$P"
xdotool mousemove --window "$WID" $((W / 2 - 80)) $((H - 120))
sleep 1
xdotool click 1
wait_title "$WID" charlie
sleep 1
shot "$WID" before-split-left "Split view with the left pane active on folder charlie (delta, one.txt, three.txt, two.txt)"
blank_double_click $((W / 2 - 80)) $((H - 120))
wait_title "$WID" bravo
shot "$WID" after-split-left "A double-click in the left pane took only that pane up to bravo (it shows folder charlie)"
pair split-left "Clicked the left pane to make it active, then double-clicked its blank space" "A double-click in the left pane takes only that pane up" "left pane active on charlie" "left pane on bravo, right unchanged" "$P"
xdotool mousemove --window "$WID" $((W - 80)) $((H - 120))
sleep 1
xdotool click 1
wait_title "$WID" alpha
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
pair root "Opened / in icon view, then double-clicked blank space and waited 2 s" "At / there is no parent, so nothing happens and no dialog opens" "/, no other window" "still /, no dialog" "$N"

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
pair pref "Opened Preferences, went to the Behavior tab and pressed Alt+P" "The new Preferences checkbox turns the feature off and stores false in xfconf" "checkbox ticked" "checkbox unticked, xfconf false" "$N"
xdotool key Escape
sleep 0.5

shot "$WID" before-off "With the checkbox unticked, the same running Thunar shows folder charlie in icon view"
blank_double_click $((W - 120)) $((H - 120))
sleep 2
[[ $(title) == *charlie* ]] || fail "with the setting off, the title changed to '$(title)'"
shot "$WID" after-off "With the setting off, a double-click on blank space left the window on folder charlie"
pair off "Closed Preferences, then double-clicked blank space in icon view and waited 2 s" "With the setting off, a blank double-click does nothing" "setting off, on charlie" "still charlie" "$N"

# Single-click mode: a double-click on a folder opens it and does not go back up
xfconf-query -c thunar -p /misc-double-click-blank-go-up -s true
xfconf-query -c thunar -p /misc-single-click -n -t bool -s true
reopen "$WORK/alpha/bravo/charlie" 1
shot "$WID" before-single "Single-click mode, blank double-click turned back on: icon view shows folder charlie with delta first"
focus "$WID"
xdotool mousemove --window "$WID" "$ITEM_X" "$ITEM_Y"
sleep 1
xdotool click --repeat 2 --delay 80 1
wait_title "$WID" delta
sleep 2
[[ $(title) == *delta* ]] || fail "in single-click mode a double-click on delta went on to '$(title)'"
shot "$WID" after-single "In single-click mode a double-click on delta left the window on delta (inside.txt), not back on charlie"
pair single "Turned on single-click mode, then double-clicked the delta folder icon and waited 2 s" "In single-click mode, a double-click on a folder opens it and does not go back up" "single-click mode, on charlie" "delta, not back on charlie" "Single-click mode"
