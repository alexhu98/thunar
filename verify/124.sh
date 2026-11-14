#!/bin/bash
# Issue #124: Select by Pattern's "Match words, like Search" checkbox, on by default and remembered until Thunar quits.
set -euo pipefail
. .github/scripts/verify-lib.sh

W=1000
H=700
DIR="$WORK/files"
G='Select by Pattern matches words, like Search (#124)'

mkdir -p "$DIR"
for f in cp-a-1pre.png cp-a-2post.png cp-b-2post.png CP-c-2post.png other-2post.png; do echo "$f" > "$DIR/$f"; done
THREE=(cp-a-2post.png cp-b-2post.png CP-c-2post.png)

keys() {
  focus "$MAIN"
  local k
  for k in "$@"; do
    xdotool key "$k"
    sleep 0.3
  done
  sleep 0.3
}

open_dialog() {
  local i
  keys ctrl+s
  for ((i = 0; i < 25; i++)); do
    DLG=$(xdotool getactivewindow 2>/dev/null) || DLG=''
    [[ -n $DLG && $(xdotool getwindowname "$DLG" 2>/dev/null) == 'Select by Pattern' ]] && return 0
    sleep 0.2
  done
  fail "Ctrl+S opened no Select by Pattern dialog"
}

dialog_keys() {
  local k
  for k in "$@"; do
    xdotool key "$k"
    sleep 0.3
  done
}

N=0
selected_is() {
  local dest got want i
  N=$((N + 1))
  dest="$WORK/check-$N"
  mkdir -p "$dest"
  keys ctrl+c
  open_thunar "$dest"
  wait_title "$WID" "check-$N"
  focus "$WID"
  xdotool key ctrl+v
  want=$(printf '%s\n' "$@" | sort | tr '\n' ' ')
  for ((i = 0; i < 25; i++)); do
    got=$(ls -A "$dest" | sort | tr '\n' ' ')
    [[ $got == "$want" ]] && break
    sleep 0.2
  done
  xdotool key ctrl+w
  sleep 0.5
  WID=$MAIN
  [[ $got == "$want" ]] || fail "check $N: the selection held '$got', expected '$want'"
}

open_thunar "$DIR"
MAIN=$WID
xdotool windowsize --sync "$MAIN" "$W" "$H"
wait_title "$MAIN" files
sleep 1

keys ctrl+a
selected_is cp-a-1pre.png "${THREE[@]}" other-2post.png
shot "$MAIN" before-words "All five files are selected before Select by Pattern runs in word mode"
open_dialog
shot "$DLG" default-on "The first dialog of the session has Match words, like Search (Ctrl+F) ticked"
xdotool type --delay 20 'cp 2post'
dialog_keys Return
selected_is "${THREE[@]}"
shot "$MAIN" after-words "cp 2post selected the three files whose name contains both cp and 2post, case ignored"
pair words "Pressed Ctrl+S, typed cp 2post with Match words on, pressed Enter" "Word mode selects names containing every word, in any order, as Search does" "All 5 files selected" "cp-a/cp-b/CP-c -2post.png selected" "$G"

keys ctrl+a
open_dialog
xdotool type --delay 20 'cp !1pre'
dialog_keys Return
selected_is "${THREE[@]}"
shot "$MAIN" exclude-word "cp !1pre selected the same three files: !1pre left out cp-a-1pre.png"

keys ctrl+a
open_dialog
dialog_keys alt+w alt+p
xdotool type --delay 20 'cp*-2post.png'
dialog_keys Return
selected_is "${THREE[@]}"

keys ctrl+a
open_dialog
shot "$DLG" remembered-off "The reopened dialog has Match words unticked and the wildcard pattern cp*-2post.png"
dialog_keys Return
selected_is "${THREE[@]}"
shot "$MAIN" wildcard-mode "Enter with the remembered wildcard pattern selected the three files, so the checkbox stayed off"

keys ctrl+a
open_dialog
dialog_keys alt+w alt+a alt+p
xdotool type --delay 20 'CP 2post'
shot "$DLG" case-on "Match words and Case sensitive are ticked, with CP 2post typed"
dialog_keys Return
selected_is CP-c-2post.png
shot "$MAIN" case-sensitive "With Case sensitive ticked, CP 2post selected only CP-c-2post.png"

keys ctrl+a
open_dialog
dialog_keys Return
selected_is "${THREE[@]}"
shot "$MAIN" case-ignored "With Case sensitive unticked again, CP 2post selected all three cp files"
