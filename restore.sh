#!/usr/bin/env bash
# Spielt ein mit backup.sh erstelltes Hyprland/Noctalia-Backup wieder ein.
# Aufruf: ./restore.sh
# Das Archiv wird immer aus dem Ordner dieses Skripts (dem Repo) gelesen.
set -euo pipefail

SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ARCHIVE="$SRC/hypr-noctalia-config.tar.gz"

if [ ! -f "$ARCHIVE" ]; then
    echo "$ARCHIVE nicht gefunden." >&2
    exit 1
fi

# Sicherheitsnetz: aktuellen Stand vor dem Ueberschreiben wegsichern, damit
# ein Restore nichts unwiderruflich zerstoert.
SAFETY="$HOME/hypr-noctalia-backup-vor-restore-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$SAFETY"
for p in .config/hypr .config/noctalia .local/state/noctalia/settings.toml .local/state/noctalia/state.toml .config/qt6ct .config/qt5ct; do
    if [ -e "$HOME/$p" ]; then
        mkdir -p "$SAFETY/$(dirname "$p")"
        cp -a "$HOME/$p" "$SAFETY/$p"
    fi
done
echo "==> Aktueller Stand vorsorglich gesichert nach: $SAFETY"

echo "==> Spiele Hyprland- und Noctalia-Konfiguration ein"
tar -C "$HOME" -xzf "$ARCHIVE"

echo "==> Fertig."
echo "    Hyprland neu laden:      hyprctl reload"
echo "    Noctalia neu starten, damit die Einstellungen uebernommen werden."
