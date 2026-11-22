#!/bin/bash
# Issue #133: F11 / F12 are second shortcuts for Drop on Previous / Next Tab (#128): they cross the split boundary like
# Alt+Page Up / Alt+Page Down, which still work, and do nothing with the focus in the location bar.
set -euo pipefail
. .github/scripts/verify-lib.sh

W=1000
H=700
LEFT=$((W / 4))
RIGHT=$((W * 3 / 4))
G='F11 / F12: Drop on Previous / Next Tab (#133)'

mkdir -p "$WORK/alpha" "$WORK/beta" "$WORK/gamma" "$WORK/delta" "$WORK/zz"
echo 1 > "$WORK/beta/f1.txt"

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

pane "$LEFT" alpha
xdotool key ctrl+Page_Down
wait_start beta
pane "$LEFT" beta
select_all
shot "$WID" before-f12 "Split view: the left pane is active on its last tab, beta, with f1.txt selected; the right pane shows gamma, empty"
xdotool key F12
wait_file "$WORK/gamma/f1.txt" present
wait_file "$WORK/beta/f1.txt" absent
sleep 1
only_in f1.txt gamma
starts beta || fail "after F12 the active tab is '$(title)', expected focus to stay on beta"
shot "$WID" after-f12 "f1.txt is now in gamma in the right pane and gone from beta, which stays active (the script asserts both folders)"
pair f12 "In the left pane's last tab, beta, selected f1.txt and pressed F12" "F12 is Drop on Next Tab and crosses the split: beta's next tab is gamma" "beta has f1.txt, gamma empty" "gamma has f1.txt, beta empty" "$G"

pane "$RIGHT" gamma
select_all
shot "$WID" before-f11 "The right pane is active on its first tab, gamma, with f1.txt selected; the left pane shows beta, empty"
xdotool key F11
wait_file "$WORK/beta/f1.txt" present
wait_file "$WORK/gamma/f1.txt" absent
sleep 1
only_in f1.txt beta
starts gamma || fail "after F11 the active tab is '$(title)', expected focus to stay on gamma"
shot "$WID" after-f11 "f1.txt is back in beta in the left pane and gone from gamma, which stays active (the script asserts both folders)"
pair f11 "In the right pane's first tab, gamma, selected f1.txt and pressed F11" "F11 is Drop on Previous Tab and crosses the split back: gamma's previous tab is beta" "gamma has f1.txt, beta empty" "beta has f1.txt, gamma empty" "$G"

pane "$LEFT" beta
select_all
shot "$WID" before-alt-next "The left pane is active on beta with f1.txt selected; gamma in the right pane is empty"
xdotool key alt+Page_Down
wait_file "$WORK/gamma/f1.txt" present
wait_file "$WORK/beta/f1.txt" absent
sleep 1
only_in f1.txt gamma
starts beta || fail "after Alt+Page Down the active tab is '$(title)', expected focus to stay on beta"
shot "$WID" after-alt-next "f1.txt is now in gamma in the right pane and gone from beta, which stays active (the script asserts both folders)"
pair alt-next "In the left pane's last tab, beta, selected f1.txt and pressed Alt+Page Down" "The original Alt+Page Down still works alongside F12" "beta has f1.txt, gamma empty" "gamma has f1.txt, beta empty" "$G"

pane "$RIGHT" gamma
select_all
shot "$WID" before-alt-previous "The right pane is active on gamma with f1.txt selected; beta in the left pane is empty"
xdotool key alt+Page_Up
wait_file "$WORK/beta/f1.txt" present
wait_file "$WORK/gamma/f1.txt" absent
sleep 1
only_in f1.txt beta
starts gamma || fail "after Alt+Page Up the active tab is '$(title)', expected focus to stay on gamma"
shot "$WID" after-alt-previous "f1.txt is back in beta in the left pane and gone from gamma, which stays active (the script asserts both folders)"
pair alt-previous "In the right pane's first tab, gamma, selected f1.txt and pressed Alt+Page Up" "The original Alt+Page Up still works alongside F11" "gamma has f1.txt, beta empty" "beta has f1.txt, gamma empty" "$G"

pane "$LEFT" beta
select_all
xdotool key ctrl+l
sleep 0.3
xdotool key ctrl+a
xdotool type --delay 5 "$WORK/zz"
sleep 0.5
shot "$WID" before-entry "The left pane's location bar holds the path of zz while f1.txt is selected in beta"
xdotool key F12
sleep 1.5
only_in f1.txt beta
xdotool key F11
sleep 1.5
only_in f1.txt beta
xdotool key Return
wait_start zz
shot "$WID" after-entry "F12 and F11 in the location bar moved nothing; Return then opened zz (the script asserts f1.txt stayed in beta)"
pair entry "Typed the path of zz in the location bar of beta, pressed F12, F11 and Return" "With the focus in a text field, F12 and F11 move no file" "location bar holds zz, f1.txt in beta" "left pane on zz, f1.txt still only in beta" "$G"
