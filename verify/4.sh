#!/bin/bash
# Issue #4: -t/--tabs and -T/--tabs-right open folders as tabs in one new window, across both split-view panes.
set -euo pipefail
. .github/scripts/verify-lib.sh

W=1000
H=700

for d in alpha beta gamma delta epsilon; do
  mkdir -p "$WORK/$d"
  echo "$d" > "$WORK/$d/in-$d.txt"
done
A=$WORK/alpha B=$WORK/beta C=$WORK/gamma D=$WORK/delta

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

windows() { xdotool search --all --onlyvisible --pid "$THUNAR_PID" --class Thunar 2>/dev/null | sort; }

count_windows() {  # expected
  local n
  n=$(windows | wc -l)
  (( n == $1 )) || fail "expected $1 Thunar windows, found $n"
}

place() {
  xdotool windowsize --sync "$WID" "$W" "$H"
  focus "$WID"
  sleep 0.5
}

pane_click() {  # x
  xdotool mousemove --window "$WID" "$1" $((H - 80))
  sleep 0.2
  xdotool click 1
  sleep 0.5
}

next_tab() {  # expected title
  focus "$WID"
  xdotool key ctrl+Page_Down
  wait_start "$1"
}

G1='thunar -t alpha beta -T gamma delta, no Thunar running'
G2='Edge cases'

open_thunar -t "$A" "$B" -T "$C" "$D"
place
wait_start alpha
count_windows 1
shot "$WID" before-left-tab "New window in split view: the left pane has tabs alpha (selected) and beta, the right pane gamma (selected) and delta; the title says alpha"
next_tab beta
shot "$WID" after-left-tab "Ctrl+Page Down moved the left pane to its second tab, beta, so keyboard focus started in the left pane"
pair left-tab "Pressed Ctrl+Page Down right after the window opened" "The left pane holds alpha then beta, alpha selected, and has the keyboard focus" "left pane on alpha, focused" "left pane on beta" "$G1"

pane_click $((W * 3 / 4))
wait_start gamma
shot "$WID" before-right-tab "After a click in the right pane the title says gamma: gamma is the right pane's selected tab"
next_tab delta
shot "$WID" after-right-tab "Ctrl+Page Down moved the right pane to its second tab, delta"
pair right-tab "Clicked in the right pane, then pressed Ctrl+Page Down" "The right pane holds gamma then delta, gamma selected" "right pane on gamma" "right pane on delta" "$G1"

xfconf-query -c thunar -p /misc-open-new-window-as-tab -n -t bool -s true
open_thunar --tabs "$A" "$B" --tabs-right "$C" "$D"
place
wait_start alpha
count_windows 2
next_tab beta
shot "$WID" long-options "With Thunar running and Open new windows as tabs on, --tabs/--tabs-right opened a second window with the same layout (the script asserts two windows and alpha then beta in the left pane)"

open_thunar -t "$A" "$B"
place
wait_start alpha
count_windows 3
next_tab beta
shot "$WID" tabs-only "thunar -t alpha beta: one new window without split view, tabs alpha and beta (the script stepped from alpha to beta)"

pushd "$WORK/epsilon" > /dev/null
open_thunar -T "$C"
popd > /dev/null
place
wait_start epsilon
pane_click $((W * 3 / 4))
wait_start gamma
pane_click $((W / 4))
wait_start epsilon
shot "$WID" right-only "thunar -T gamma run in epsilon: the left pane shows epsilon, the current directory, and the right pane gamma"

before=$(windows)
rc=0
thunar -T 2> "$WORK/err.txt" || rc=$?
(( rc == 1 )) || fail "thunar -T exited with $rc, expected 1"
grep -q -- '--tabs-right needs at least one location' "$WORK/err.txt" || fail "thunar -T printed '$(cat "$WORK/err.txt")'"
sleep 1
[[ $(windows) == "$before" ]] || fail "thunar -T opened a window"

before=$(windows)
thunar -t "$A" "$WORK/missing" "$B" &
ERR=''
for ((i = 0; i < 50; i++)); do
  ERR=$(xdotool search --onlyvisible --name '^Error$' 2>/dev/null | head -1) && [[ -n $ERR ]] && break
  sleep 0.2
done
[[ -n $ERR ]] || fail "no error dialog for the missing location"
before=$(printf '%s\n%s\n' "$before" "$ERR" | sort)
shot "$ERR" before-missing "Thunar's Failed to open error dialog for the location missing, which doesn't exist"
focus "$ERR"
xdotool key Return
WID=''
for ((i = 0; i < 50; i++)); do
  WID=$(comm -13 <(echo "$before") <(windows) | head -1)
  [[ -n $WID ]] && break
  sleep 0.2
done
[[ -n $WID ]] || fail "no window opened after the error"
place
wait_start alpha
next_tab beta
shot "$WID" after-missing "After the error, the window still opened with tabs alpha and beta (the script stepped from alpha to beta)"
pair missing "Ran thunar -t alpha missing beta and dismissed the error" "A missing location gets the usual error and the other tabs still open" "error: Failed to open missing" "window with tabs alpha and beta" "$G2"

help=$(thunar --help)
grep -q -- '-t, --tabs' <<<"$help" || fail "thunar --help doesn't list -t, --tabs"
grep -q -- '-T, --tabs-right' <<<"$help" || fail "thunar --help doesn't list -T, --tabs-right"
echo "PASS"
