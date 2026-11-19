#!/bin/bash
# Issue #128: Alt+Page Up / Alt+Page Down drop the selection on the previous / next tab, crossing the split boundary;
# nothing happens past the first or last tab, or with the focus in the location bar; without split view it works
# across the tabs of the one pane.
set -euo pipefail
. .github/scripts/verify-lib.sh

W=1000
H=700
LEFT=$((W / 4))
RIGHT=$((W * 3 / 4))
G='Drop on Previous / Next Tab (#128)'

mkdir -p "$WORK/alpha" "$WORK/beta" "$WORK/gamma" "$WORK/delta" "$WORK/echo" "$WORK/foxtrot" "$WORK/zz"
echo 1 > "$WORK/beta/f1.txt"
echo g > "$WORK/alpha/g.txt"
echo h > "$WORK/delta/h.txt"
echo k > "$WORK/echo/k.txt"

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

wait_file() {  # path present|absent
  local i
  for ((i = 0; i < 50; i++)); do
    if [[ $2 == present ]]; then [[ -e $1 ]] && return 0; else [[ ! -e $1 ]] && return 0; fi
    sleep 0.2
  done
  fail "expected $1 to be $2"
}

only_in() {  # file folder
  local d
  for d in alpha beta gamma delta; do
    if [[ $d == "$2" ]]; then
      [[ -e $WORK/$d/$1 ]] || fail "$1 is missing from $d"
    else
      [[ ! -e $WORK/$d/$1 ]] || fail "$1 is in $d, expected it only in $2"
    fi
  done
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

select_all() {
  xdotool key ctrl+a
  sleep 0.5
}

open_thunar --split=50 -t "$WORK/alpha" "$WORK/beta" -T "$WORK/gamma" "$WORK/delta"
xdotool windowsize --sync "$WID" "$W" "$H"
wait_start alpha
focus "$WID"
sleep 1

# Alt+Page Down from the left pane's last tab drops on the right pane's first tab
pane "$LEFT" alpha
xdotool key ctrl+Page_Down
wait_start beta
pane "$LEFT" beta
select_all
shot "$WID" before-next "Split view: the left pane is active on its second tab, beta, with f1.txt selected; the right pane shows gamma, empty"
xdotool key alt+Page_Down
wait_file "$WORK/gamma/f1.txt" present
wait_file "$WORK/beta/f1.txt" absent
sleep 1
only_in f1.txt gamma
starts beta || fail "after Alt+Page Down the active tab is '$(title)', expected focus to stay on beta"
shot "$WID" after-next "f1.txt is now in gamma in the right pane and gone from beta, which stays active (the script asserts both folders)"
pair next "In the left pane's last tab, beta, selected f1.txt and pressed Alt+Page Down" "Drop on Next Tab crosses the split: beta's next tab is the right pane's first, gamma" "beta has f1.txt, gamma empty" "gamma has f1.txt, beta empty" "$G"

# Alt+Page Up from the right pane's first tab drops on the left pane's last tab
pane "$RIGHT" gamma
select_all
shot "$WID" before-previous "The right pane is active on its first tab, gamma, with f1.txt selected; the left pane shows beta, empty"
xdotool key alt+Page_Up
wait_file "$WORK/beta/f1.txt" present
wait_file "$WORK/gamma/f1.txt" absent
sleep 1
only_in f1.txt beta
starts gamma || fail "after Alt+Page Up the active tab is '$(title)', expected focus to stay on gamma"
shot "$WID" after-previous "f1.txt is back in beta in the left pane and gone from gamma, which stays active (the script asserts both folders)"
pair previous "In the right pane's first tab, gamma, selected f1.txt and pressed Alt+Page Up" "Drop on Previous Tab crosses the split back: gamma's previous tab is beta" "gamma has f1.txt, beta empty" "beta has f1.txt, gamma empty" "$G"

# Past the first and the last tab nothing happens
pane "$LEFT" beta
xdotool key ctrl+Page_Up
wait_start alpha
pane "$LEFT" alpha
select_all
shot "$WID" before-first "The left pane is active on the first tab, alpha, with g.txt selected"
xdotool key alt+Page_Up
sleep 1.5
only_in g.txt alpha
starts alpha || fail "Alt+Page Up on the first tab changed the window to '$(title)'"
shot "$WID" after-first "1.5 s after Alt+Page Up on the first tab, g.txt is still only in alpha (the script asserts it)"
pair first "On the first tab, alpha, selected g.txt and pressed Alt+Page Up" "There is no tab before the first, and no wrap-around: nothing moves" "alpha has g.txt selected" "g.txt still only in alpha" "$G"

pane "$RIGHT" gamma
xdotool key ctrl+Page_Down
wait_start delta
pane "$RIGHT" delta
select_all
shot "$WID" before-last "The right pane is active on the last tab, delta, with h.txt selected"
xdotool key alt+Page_Down
sleep 1.5
only_in h.txt delta
starts delta || fail "Alt+Page Down on the last tab changed the window to '$(title)'"
shot "$WID" after-last "1.5 s after Alt+Page Down on the last tab, h.txt is still only in delta (the script asserts it)"
pair last "On the last tab, delta, selected h.txt and pressed Alt+Page Down" "There is no tab after the last, and no wrap-around: nothing moves" "delta has h.txt selected" "h.txt still only in delta" "$G"

# In the location bar Alt+Page Down moves no file
pane "$LEFT" alpha
select_all
xdotool key ctrl+l
sleep 0.3
xdotool key ctrl+a
xdotool type --delay 5 "$WORK/zz"
sleep 0.5
shot "$WID" before-entry "The left pane's location bar holds the path of zz while g.txt is selected in alpha"
xdotool key alt+Page_Down
sleep 1.5
only_in g.txt alpha
xdotool key Return
wait_start zz
shot "$WID" after-entry "Alt+Page Down in the location bar moved nothing; Return then opened zz (the script asserts g.txt stayed in alpha)"
pair entry "Typed the path of zz in the location bar of alpha, pressed Alt+Page Down and Return" "With the focus in a text field, Alt+Page Down moves no file" "location bar holds zz, g.txt in alpha" "left pane on zz, g.txt still only in alpha" "$G"

# Without split view it works across the tabs of the one pane
open_thunar -t "$WORK/echo" "$WORK/foxtrot"
xdotool windowsize --sync "$WID" "$W" "$H"
wait_start echo
focus "$WID"
sleep 1
pane $((W / 2)) echo
select_all
shot "$WID" before-no-split "A window without split view on its first tab, echo, with k.txt selected; its second tab is foxtrot"
xdotool key alt+Page_Down
wait_file "$WORK/foxtrot/k.txt" present
wait_file "$WORK/echo/k.txt" absent
sleep 1
starts echo || fail "after Alt+Page Down the active tab is '$(title)', expected focus to stay on echo"
shot "$WID" after-no-split "k.txt is gone from echo, which stays active; the script asserts it is now in foxtrot"
pair no-split "Without split view, selected k.txt in the first tab, echo, and pressed Alt+Page Down" "Without split view Drop on Next Tab moves the selection to the pane's next tab" "echo has k.txt, foxtrot empty" "echo empty, k.txt in foxtrot" "$G"
