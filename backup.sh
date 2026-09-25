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

# Noctalia speichert in settings.toml nur den Pfad zum Hintergrundbild --
# die Bilddateien selbst muessen daher separat mitgesichert werden.
SETTINGS="$HOME/.local/state/noctalia/settings.toml"
if [ -f "$SETTINGS" ]; then
    while IFS= read -r wp; do
        [ -z "$wp" ] && continue
        wp="${wp/#\~/$HOME}"
        if [ ! -f "$wp" ]; then
            echo "    Warnung: Hintergrundbild $wp nicht gefunden, uebersprungen." >&2
            continue
        fi
        case "$wp" in
            "$HOME"/*) rel="${wp#"$HOME"/}" ;;
            *) echo "    Warnung: $wp liegt ausserhalb von $HOME, uebersprungen." >&2; continue ;;
        esac
        # Doppelte Eintraege (default/last/monitors) nur einmal aufnehmen
        [[ " ${EXISTING[*]} " == *" $rel "* ]] || EXISTING+=("$rel")
    done < <(awk '
        /^\[/ { in_wp = ($0 ~ /^\[wallpaper(\.|\])/) }
        in_wp && /^[[:space:]]*path[[:space:]]*=/ {
            sub(/^[^=]*=[[:space:]]*"/, ""); sub(/"[[:space:]]*$/, ""); print
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
