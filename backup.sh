#!/usr/bin/env bash
# Sichert Hyprland- und Noctalia-Konfiguration plus die restliche Desktop-
# Umgebung (Shell, Terminal, GTK, Standard-Apps, Pakete, Dienste, Flatpaks).
# Aufruf: ./backup.sh
# Das Archiv wird immer im Ordner dieses Skripts (dem Repo) abgelegt.
set -euo pipefail

DEST="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "==> Sichere Hyprland- und Noctalia-Konfiguration nach $DEST"

# Reine Konfigurationspfade. Noctalia legt echte Live-Settings zusaetzlich
# unter .local/state ab (nicht nur .config) -- daher beide Orte sichern.
# Cache/Downloads/Verlauf (community-templates, clipboard, notification_history
# usw.) werden bewusst NICHT gesichert: kein Konfigzustand, teils sensibel
# (Clipboard-Verlauf) und regenerierbar.
CONFIG_PATHS=(
    ".config/hypr"
    ".config/noctalia"
    ".local/state/noctalia/settings.toml"
    ".local/state/noctalia/state.toml"
    # Daten/Anpassungen aller Noctalia-Plugins (z.B. ausgeblendete Binds im
    # Keybind-Cheatsheet). Der Plugin-Code selbst kommt aus dem Plugin-Repo.
    ".local/state/noctalia/plugins/data"
    # UWSM-Umgebung (Cursor-Theme, Qt-Plattformtheme usw.), siehe environment.lua
    ".config/uwsm"
    # Von hypr-persist gespeicherte Fensteranordnung (Autostart: restore startup)
    ".local/share/hypr-persist/sessions"
    ".config/qt6ct"
    ".config/qt5ct"
    # Restliche Desktop-Umgebung
    ".config/fish"
    ".config/alacritty"
    ".config/kitty"
    # Standard-Terminal fuer xdg-terminal-exec (u.a. arch-update-Tray, gio,
    # .desktop-Dateien mit Terminal=true)
    ".config/xdg-terminals.list"
    ".config/gtk-3.0"
    ".config/gtk-4.0"
    ".config/mimeapps.list"
    # KDE-Cursor/Touchpad. KDE synchronisiert seinen Cursor nach GTK/dconf --
    # ohne Eintrag hier ueberschreibt es Bibata mit dem Default breeze_cursors.
    ".config/kcminputrc"
    # Standard-Cursor fuer Apps, die kein Theme gesetzt bekommen (XWayland usw.)
    ".local/share/icons/default/index.theme"
    # MakeMKV ist eine Qt5-App: QT_QPA_PLATFORMTHEME=qt6ct greift dort nicht,
    # daher Starter mit qt5ct (Farben kommen von Noctalia nach ~/.config/qt5ct)
    ".local/share/applications/makemkv.desktop"
    # hyfetch (Terminal-Begruessung der CachyOS-fish-Config); Backend ist
    # fastfetch, das ohne eigene Config laeuft -- falls doch eine angelegt
    # wird, kommt sie automatisch mit.
    ".config/hyfetch.json"
    ".config/fastfetch"
)

EXISTING=()
for p in "${CONFIG_PATHS[@]}"; do
    [ -e "$HOME/$p" ] && EXISTING+=("$p")
done

# Noctalia speichert in settings.toml nur Pfade zu den Hintergrundbildern --
# die Bilddateien selbst muessen daher separat mitgesichert werden. Gesichert
# wird der komplette Rotationsordner (wallpaper.directory) plus alle einzeln
# gesetzten Bilder (default/last/monitors), sofern sie nicht darin liegen.
SETTINGS="$HOME/.local/state/noctalia/settings.toml"
WP_DIRS=()
if [ -f "$SETTINGS" ]; then
    while IFS=$'\t' read -r kind wp; do
        [ -z "$wp" ] && continue
        wp="${wp/#\~/$HOME}"
        wp="${wp%/}"
        if [ "$kind" = dir ]; then
            label="Hintergrundbild-Ordner"
            [ -d "$wp" ] || { echo "    Warnung: $label $wp nicht gefunden, uebersprungen." >&2; continue; }
        else
            label="Hintergrundbild"
            [ -f "$wp" ] || { echo "    Warnung: $label $wp nicht gefunden, uebersprungen." >&2; continue; }
            # Liegt das Bild im bereits gesicherten Ordner, nicht doppelt aufnehmen
            for d in "${WP_DIRS[@]}"; do
                [[ "$wp" == "$d"/* ]] && continue 2
            done
        fi
        case "$wp" in
            "$HOME"/*) rel="${wp#"$HOME"/}" ;;
            *) echo "    Warnung: $label $wp liegt ausserhalb von $HOME, uebersprungen." >&2; continue ;;
        esac
        [ "$kind" = dir ] && WP_DIRS+=("$wp")
        EXISTING+=("$rel")
    # awk gibt erst die Ordner, dann die Einzelbilder aus und entfernt
    # Doppelte (default/last/monitors), damit Warnungen nur einmal erscheinen.
    # Noctalia rueckt Untertabellen ein, daher Whitespace vor "[" erlauben.
    done < <(awk '
        /^[[:space:]]*\[/ { in_wp = ($0 ~ /^[[:space:]]*\[wallpaper(\.|\])/) }
        in_wp && /^[[:space:]]*(directory|path)[[:space:]]*=/ {
            key = ($0 ~ /^[[:space:]]*directory/) ? "dir" : "file"
            sub(/^[^=]*=[[:space:]]*"/, ""); sub(/"[[:space:]]*$/, "")
            if (seen[key, $0]++) next
            if (key == "dir") dirs[++nd] = $0; else files[++nf] = $0
        }
        END {
            for (i = 1; i <= nd; i++) print "dir\t" dirs[i]
            for (i = 1; i <= nf; i++) print "file\t" files[i]
        }' "$SETTINGS")
fi

if [ "${#EXISTING[@]}" -eq 0 ]; then
    echo "Keine der erwarteten Pfade gefunden, breche ab." >&2
    exit 1
fi

tar -C "$HOME" -czf "$DEST/hypr-noctalia-config.tar.gz" "${EXISTING[@]}"

# Paketliste fuer ein neues System: explizit installierte Pakete, getrennt
# nach Repo-Paketen (pacman) und AUR/Fremdpaketen (AUR-Helper).
pacman -Qqen > "$DEST/pkglist-repo.txt"
pacman -Qqem > "$DEST/pkglist-aur.txt"

# GTK/GNOME-Einstellungen (Theme, Icons, Schriften, Nautilus usw.). Die
# Binaerdatei ~/.config/dconf/user ist nicht portabel, daher als Text-Dump.
if command -v dconf >/dev/null; then
    dconf dump / > "$DEST/dconf.ini"
fi

# Aktivierte systemd-Units (System und Benutzer). Template-Units (getty@.service
# usw.) werden ausgelassen, die lassen sich nicht ohne Instanz aktivieren.
systemctl list-unit-files --state=enabled --no-legend \
    | awk '$1 !~ /@\./ {print $1}' > "$DEST/services-system.txt"
systemctl --user list-unit-files --state=enabled --no-legend \
    | awk '$1 !~ /@\./ {print $1}' > "$DEST/services-user.txt"

# Flatpak-Apps als "App-ID<TAB>Remote<TAB>Installation (system/user)"
if command -v flatpak >/dev/null; then
    flatpak list --app --columns=application,origin,installation > "$DEST/flatpaks.txt"
fi

echo "==> Fertig. Backup liegt in: $DEST"
echo "    - hypr-noctalia-config.tar.gz  (${#EXISTING[@]} Pfade gesichert, $(date '+%d.%m.%Y %H:%M'))"
for p in "${EXISTING[@]}"; do
    echo "        * $p"
done
echo "    - pkglist-repo.txt  ($(wc -l < "$DEST/pkglist-repo.txt") Pakete)"
echo "    - pkglist-aur.txt   ($(wc -l < "$DEST/pkglist-aur.txt") Pakete)"
[ -f "$DEST/dconf.ini" ] && echo "    - dconf.ini         ($(grep -c '^\[' "$DEST/dconf.ini") Bereiche)"
echo "    - services-system.txt ($(wc -l < "$DEST/services-system.txt") Units)"
echo "    - services-user.txt   ($(wc -l < "$DEST/services-user.txt") Units)"
[ -f "$DEST/flatpaks.txt" ] && echo "    - flatpaks.txt      ($(wc -l < "$DEST/flatpaks.txt") Apps)"
