#!/bin/bash
# Issue #149: Ctrl+F searches the current folder and its subfolders, Ctrl+Shift+F only the current folder.
set -euo pipefail
. .github/scripts/verify-lib.sh

W=1000
H=700
TOGGLE_X=$((W - 60))
TOGGLE_Y=45
SEARCH_X=$((W - 20))
SEARCH_Y=45

mkdir -p "$WORK/top/sub"
echo top > "$WORK/top/match-top.txt"
echo sub > "$WORK/top/sub/match-sub.txt"

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

search() {  # key that opens the search, query
  focus "$WID"
  xdotool key "$1"
  sleep 0.5
  xdotool type --delay 20 "$2"
  sleep 2
}

cancel_search() {
  focus "$WID"
  xdotool key Escape
  sleep 1
}

click_at() {  # x y
  focus "$WID"
  xdotool mousemove --window "$WID" "$1" "$2"
  sleep 0.5
  xdotool click 1
  xdotool mousemove --window "$WID" $((W / 2)) $((H - 40))
  sleep 0.5
}

results_are() {  # check name, the files the folder view must list
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
  fail "the view listed '$got', expected '$want'"
}

saved() {  # folder
  gio info -a metadata::thunar-search-subfolders "$1" 2>/dev/null | sed -n 's/^ *metadata::thunar-search-subfolders: //p'
}

ON_DISK=0
SKIPPED=
[[ $(gio info -w "$WORK" 2>/dev/null) == *metadata* ]] && ON_DISK=1
(( ON_DISK )) || SKIPPED="GIO metadata is not writable here (no gvfs)"
skipped() { [[ -z $SKIPPED ]] || echo " ($SKIPPED, so the on-disk check was skipped)"; }

saved_is() {  # true or false
  (( ON_DISK )) || return 0
  [[ $(saved "$WORK/top") == "$1" ]] || fail "top's saved choice is '$(saved "$WORK/top")', expected '$1'"
}

open_thunar "$WORK/top"
xdotool windowsize --sync "$WID" "$W" "$H"
wait_title "$WID" top
focus "$WID"
xdotool key ctrl+2
sleep 0.5

S='Ctrl+F and Ctrl+Shift+F choose the search scope'
B='The toolbar Search button keeps the folder'"'"'s saved choice'

search ctrl+shift+f match
saved_is false
shot "$WID" before-subfolders "Ctrl+Shift+F in top with the global default Always: the Include subfolders toggle is released and only match-top.txt is listed"
cancel_search
search ctrl+f match
saved_is true
shot "$WID" after-subfolders "Ctrl+F in top: the Include subfolders toggle is pressed and both match-top.txt and sub/match-sub.txt are listed"
pair subfolders "Ended the Ctrl+Shift+F search with Escape, pressed Ctrl+F and typed match" "Ctrl+F searches top with its subfolders, Ctrl+Shift+F without them$(skipped)" "Ctrl+Shift+F: toggle off, only match-top.txt" "Ctrl+F: toggle on, both files" "$S"
cancel_search

shot "$WID" before-folder "Folder top with no search running, listing match-top.txt and the sub folder; Ctrl+F saved Include subfolders on for it"
search ctrl+shift+f match
saved_is false
shot "$WID" after-folder "Ctrl+Shift+F in top still searches only the current folder: the Include subfolders toggle is released and only match-top.txt is listed"
pair folder "Pressed Ctrl+Shift+F in top and typed match" "Ctrl+Shift+F searches only the current folder, even where subfolders were saved on$(skipped)" "top, subfolders saved on, no search" "toggle off, only match-top.txt" "$S"
cancel_search

shot "$WID" before-toolbar "Folder top with no search running, listing match-top.txt and the sub folder; Ctrl+Shift+F saved Include subfolders off for it"
click_at "$SEARCH_X" "$SEARCH_Y"
xdotool type --delay 20 match
sleep 2
saved_is false
shot "$WID" after-toolbar "The toolbar Search button in top opens with the saved choice, not the global Always: the toggle is released and only match-top.txt is listed"
pair toolbar "Clicked the Search button at the right of the toolbar and typed match" "The toolbar button opens with the folder's saved choice, off since Ctrl+Shift+F" "top, subfolders saved off, no search" "toggle off, only match-top.txt" "$B"
results_are toolbar match-top.txt

go "$WORK/top"
search ctrl+f match
results_are ctrl-f match-sub.txt match-top.txt

go "$WORK/top"
search ctrl+f match
click_at "$TOGGLE_X" "$TOGGLE_Y"
sleep 1.5
saved_is false
results_are toggle match-top.txt

go "$WORK/top"
search ctrl+shift+f match
focus "$WID"
xdotool key ctrl+f
sleep 1.5
results_are ends match-top.txt sub

go "$WORK/top"
focus "$WID"
xdotool key alt+g
sleep 1
shot root go-menu "The Go menu lists Search in Subfolders... with Ctrl+F above Search for Files... with Ctrl+Shift+F"
xdotool key u
sleep 0.5
xdotool type --delay 20 match
sleep 2
results_are go-subfolders match-sub.txt match-top.txt

go "$WORK/top"
focus "$WID"
xdotool key alt+g
sleep 1
xdotool key s
sleep 0.5
xdotool type --delay 20 match
sleep 2
results_are go-folder match-top.txt

(( ON_DISK )) || echo "note: $SKIPPED, so the on-disk checks were skipped" >&2
