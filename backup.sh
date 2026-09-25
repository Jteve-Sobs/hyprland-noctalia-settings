#!/usr/bin/env bash
# Sichert Hyprland- und Noctalia-Konfiguration.
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
    ".config/qt6ct"
    ".config/qt5ct"
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

echo "==> Fertig. Backup liegt in: $DEST"
echo "    - hypr-noctalia-config.tar.gz  (${#EXISTING[@]} Pfade gesichert, $(date '+%d.%m.%Y %H:%M'))"
for p in "${EXISTING[@]}"; do
    echo "        * $p"
done
