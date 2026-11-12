#!/bin/bash
# Issue #17: the side pane has a Bookmarks section, and Places shows the standard folders.
set -euo pipefail
. .github/scripts/verify-lib.sh

W=1000
H=760
PANE_X=70
TOP_Y=84
STEP=10

CONF=${XDG_CONFIG_HOME:-$HOME/.config}
mkdir -p "$CONF/gtk-3.0" "$HOME/Desktop" "$HOME/Documents" "$HOME/Music" "$HOME/Pictures" \
  "$WORK/data/Downloads" "$WORK/data/Videos" "$WORK/projects" "$WORK/notes" "$WORK/start"
echo marker > "$WORK/data/Downloads/in-data-downloads.txt"
ln -s "$WORK/data/Downloads" "$HOME/Downloads"
ln -s "$WORK/data/Videos" "$HOME/Videos"
cat > "$CONF/user-dirs.dirs" <<'EOF'
XDG_DESKTOP_DIR="$HOME/Desktop"
XDG_DOCUMENTS_DIR="$HOME/Documents"
XDG_DOWNLOAD_DIR="$HOME/Downloads"
XDG_MUSIC_DIR="$HOME/Music"
XDG_PICTURES_DIR="$HOME/Pictures"
XDG_VIDEOS_DIR="$HOME/Videos"
XDG_TEMPLATES_DIR="$HOME"
EOF
printf 'file://%s\nfile://%s\n' "$WORK/projects" "$WORK/notes" > "$CONF/gtk-3.0/bookmarks"
BOOKMARKS_BEFORE=$(cat "$CONF/gtk-3.0/bookmarks")


title() { local t; t=$(xdotool getwindowname "$WID"); echo "${t%% - *}"; }

# Clicks down the side pane and records, in order, each folder it opened (NAMES) and the first y that opened it (YS).
# Stops at File System, the first Devices row.
scan() {
  local y t prev
  NAMES=() YS=()
  focus "$WID"
  prev=$(title)
  for ((y = TOP_Y; y < H - 10; y += STEP)); do
    xdotool mousemove --window "$WID" "$PANE_X" "$y" click 1
    sleep 0.25
    t=$(title)
    [[ $t == "$prev" ]] && continue
    NAMES+=("$t") YS+=("$y")
    prev=$t
    [[ $t != "File System" && $t != / ]] || return 0
  done
  fail "side pane scan reached the bottom without a Devices row; it opened: ${NAMES[*]}"
}

index_of() {  # name -> index in NAMES, or -1
  local i
  for i in "${!NAMES[@]}"; do [[ ${NAMES[$i]} == "$1" ]] && { echo "$i"; return; }; done
  echo -1
}

y_of() { local i; i=$(index_of "$1"); ((i >= 0)) || fail "$1 is not in the side pane: ${NAMES[*]}"; echo "${YS[$i]}"; }

before() {  # a b: a comes before b in the side pane
  local a b
  a=$(index_of "$1") b=$(index_of "$2")
  ((a >= 0 && b >= 0 && a < b)) || fail "expected $1 before $2 in the side pane: ${NAMES[*]}"
}

hidden_has() {  # path: hidden-bookmarks holds its URI
  xfconf-query -c thunar -p /hidden-bookmarks 2>/dev/null | grep -qF "file://$1" \
    || fail "file://$1 is not in hidden-bookmarks: $(xfconf-query -c thunar -p /hidden-bookmarks 2>&1)"
}

# Right-clicks the header just above the row first hit at Y and toggles entry ENTRY of the header menu's submenu SECTION (1-based both).
toggle() {  # y section entry shotname proves
  local y=$(($1 - 12)) i
  focus "$WID"
  xdotool mousemove --window "$WID" "$PANE_X" "$y" click 3
  sleep 0.6
  for ((i = 0; i < $2; i++)); do xdotool key Down; done
  xdotool key Right
  for ((i = 1; i < $3; i++)); do xdotool key Down; done
  sleep 0.5
  [[ -z ${4:-} ]] || shot root "$4" "$5"
  xdotool key Return
  sleep 0.8
}

open_thunar "$WORK/start"
xdotool windowsize --sync "$WID" "$W" "$H"
wait_title "$WID" start
sleep 1

scan
echo "side pane: ${NAMES[*]} at y ${YS[*]}"
for name in Desktop Documents Downloads Music Pictures Videos projects notes; do
  [[ $(index_of "$name") -ge 0 ]] || fail "$name is not in the side pane: ${NAMES[*]}"
done
before Desktop Documents
before Documents Downloads
before Downloads Music
before Music Pictures
before Pictures Videos
before Videos projects
before projects notes
[[ $(index_of Trash) -lt 0 ]] || before Trash projects
[[ $(index_of Recent) -lt 0 ]] || before Videos Recent
before notes "${NAMES[-1]}"

xdotool mousemove --window "$WID" "$PANE_X" "$(y_of Downloads)" click 1
wait_title "$WID" Downloads
xdotool mousemove --window "$WID" $((W - 100)) $((H - 100))
shot "$WID" before-hide-bookmarks "Places lists Desktop, Documents, Downloads, Music, Pictures and Videos before Trash, then a Bookmarks header over projects and notes, then Devices; Downloads is open and shows in-data-downloads.txt, the file in the folder its symlink points to"


# Hide projects from the Bookmarks header's menu, then notes, which empties the section
toggle "$(y_of projects)" 2 1 bookmarks-menu "The Bookmarks header's right-click menu is open on its Bookmarks submenu, which lists projects and notes, each with a checked show/hide box"
hidden_has "$WORK/projects"
toggle "$(y_of projects)" 2 2
hidden_has "$WORK/notes"
xdotool mousemove --window "$WID" $((W - 100)) $((H - 100))
shot "$WID" after-hide-bookmarks "With projects and notes hidden, the Bookmarks header is gone too: Places is followed directly by the Devices header"
pair hide-bookmarks "Unticked projects, then notes, in the Bookmarks header's right-click menu" "Bookmarks can be hidden from their header's menu, and the header hides when every bookmark is hidden" "Bookmarks: projects, notes" "Both hidden: no Bookmarks header" "Bookmarks section"
[[ $(cat "$CONF/gtk-3.0/bookmarks") == "$BOOKMARKS_BEFORE" ]] || fail "hiding bookmarks changed the bookmarks file"

# Hide Downloads from the Places submenu, then restart Thunar
DL=$(($(index_of Downloads) + 1))
shot "$WID" before-hide-downloads "Places lists Downloads between Documents and Music"
toggle "${YS[0]}" 1 "$DL"
hidden_has "$HOME/Downloads"

kill "$THUNAR_PID"
for ((i = 0; i < 50; i++)); do kill -0 "$THUNAR_PID" 2>/dev/null || break; sleep 0.2; done
unset THUNAR_PID
open_thunar "$WORK/start"
xdotool windowsize --sync "$WID" "$W" "$H"
wait_title "$WID" start
sleep 1
scan
echo "side pane after restart: ${NAMES[*]}"
for name in Downloads projects notes; do
  [[ $(index_of "$name") -lt 0 ]] || fail "$name came back after a restart: ${NAMES[*]}"
done
before Documents Music
xdotool mousemove --window "$WID" $((W - 100)) $((H - 100))
shot "$WID" after-hide-downloads "After a restart Places goes from Documents straight to Music, without Downloads, and the Bookmarks section is still hidden"
pair hide-downloads "Unticked Downloads in the Places submenu, then quit and restarted Thunar" "A standard folder can be hidden, and hidden entries stay hidden after a restart" "Downloads in Places" "Restarted: Downloads still hidden" "Standard folders"
