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
