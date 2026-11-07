#!/bin/bash
# Issue #21: an "Include subfolders" toggle in the search bar, saved per folder.
set -euo pipefail
. .github/scripts/verify-lib.sh

W=1000
H=700
TOGGLE_X=$((W - 60))
TOGGLE_Y=45

mkdir -p "$WORK/top/sub" "$WORK/other/deep"
echo top > "$WORK/top/match-top.txt"
echo sub > "$WORK/top/sub/match-sub.txt"
echo other > "$WORK/other/match-other.txt"
echo deep > "$WORK/other/deep/match-deep.txt"

go() {  # path
  focus "$WID"
  xdotool key ctrl+l
  sleep 0.3
  xdotool type --delay 5 "$1"
  xdotool key Return
  wait_title "$WID" "$(basename "$1")"
  xdotool key Escape
  sleep 0.5
}

search() {  # query
  focus "$WID"
  xdotool key ctrl+f
  sleep 0.5
  xdotool type --delay 20 "$1"
  sleep 2
}

cancel_search() {
  focus "$WID"
  xdotool key Escape
  sleep 1
}

toggle_subfolders() {
  focus "$WID"
  xdotool mousemove --window "$WID" "$TOGGLE_X" "$TOGGLE_Y"
  sleep 0.5
  xdotool click 1
  xdotool mousemove --window "$WID" $((W / 2)) $((H - 40))
  sleep 2
}

results_are() {  # check name, the files the search must list
  local dest="$WORK/check-$1" got want i
  shift
  mkdir -p "$dest"
  focus "$WID"
  xdotool mousemove --window "$WID" $((W / 2)) $((H - 100)) click 1
  sleep 0.5
  xdotool key ctrl+a ctrl+c
  sleep 0.5
  cancel_search
  go "$dest"
  xdotool key ctrl+v
  want=$(printf '%s\n' "$@" | sort | tr '\n' ' ')
  for ((i = 0; i < 25; i++)); do
    got=$(ls -A "$dest" | sort | tr '\n' ' ')
    [[ $got == "$want" ]] && return 0
    sleep 0.2
  done
  fail "the search listed '$got', expected '$want'"
}

saved() {  # folder
  gio info -a metadata::thunar-search-subfolders "$1" 2>/dev/null | sed -n 's/^ *metadata::thunar-search-subfolders: //p'
}

ON_DISK=0
gio info -w "$WORK" 2>/dev/null | grep -q 'metadata' && ON_DISK=1

metadata_on_disk() {
  (( ON_DISK ))
}

start_thunar() {
  open_thunar "$WORK/top"
  xdotool windowsize --sync "$WID" "$W" "$H"
  wait_title "$WID" top
  focus "$WID"
  xdotool key ctrl+2
  sleep 0.5
}

S='The toggle searches subfolders or not'
R='The choice is saved for the folder'

start_thunar

search match
shot "$WID" before-off "Searching top for match with the global default (Always): the Include subfolders toggle is pressed and both match-top.txt and sub/match-sub.txt are listed"
toggle_subfolders
if metadata_on_disk; then
  [[ $(saved "$WORK/top") == false ]] || fail "toggling off did not save false for top (got '$(saved "$WORK/top")')"
fi
shot "$WID" after-off "With the Include subfolders toggle released, the same search in top lists only match-top.txt"
results_are off match-top.txt
pair off "Clicked the Include subfolders toggle beside the search field" "Turning the toggle off re-runs the search in top without its subfolders" "toggle on, both files" "toggle off, only match-top.txt" "$S"

go "$WORK/other"
search match
shot "$WID" other-default "Searching another folder, other, still follows the global default: the toggle is pressed and match-other.txt and deep/match-deep.txt are both listed"
results_are other match-deep.txt match-other.txt

go "$WORK/top"
shot "$WID" before-reopen "Back in folder top with no search running (match-top.txt and the sub folder)"
search match
shot "$WID" after-reopen "A new search in top comes back with the toggle released and lists only match-top.txt"
pair reopen "Left top for other, came back and searched for match again" "top remembers its saved choice: subfolders stay off there" "top, no search" "toggle off again, only match-top.txt" "$R"
results_are reopen match-top.txt

if metadata_on_disk; then
  kill "$THUNAR_PID"
  wait "$THUNAR_PID" 2>/dev/null || true
  unset THUNAR_PID
  start_thunar
  search match
  results_are restart match-top.txt
fi

go "$WORK/top"
focus "$WID"
xdotool key alt+v
sleep 1
shot root before-clear "The whole screen: folder top with its saved choice off, and the View menu open, listing Clear Saved Folder View Settings"
xdotool key e
sleep 2
if metadata_on_disk; then
  [[ -z $(saved "$WORK/top") ]] || fail "Clear Saved Folder View Settings left '$(saved "$WORK/top")' for top"
fi
search match
shot "$WID" after-clear "After Clear Saved Folder View Settings, a search in top follows the global default again: the toggle is pressed and both files are listed"
pair clear "Chose View > Clear Saved Folder View Settings, then searched top for match" "Clearing the folder's saved view settings also clears its Include subfolders choice" "top saved off, View menu open" "default again: toggle on, both files" "$R"
results_are clear match-sub.txt match-top.txt

go "$WORK/top"
focus "$WID"
xdotool key ctrl+l
sleep 0.3
xdotool type --delay 20 "Search: match"
sleep 2
toggle_subfolders
results_are typed match-top.txt

if ! metadata_on_disk; then
  echo "note: GIO metadata is not writable here (no gvfs), so the on-disk checks were skipped" >&2
fi
