#!/usr/bin/env bash
# Spielt ein mit backup.sh erstelltes Hyprland/Noctalia-Backup wieder ein.
# Aufruf: ./restore.sh
# Das Archiv wird immer aus dem Ordner dieses Skripts (dem Repo) gelesen.
# Pakete, Flatpaks und Dienste werden nur nach Rueckfrage angefasst.
set -euo pipefail

SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ARCHIVE="$SRC/hypr-noctalia-config.tar.gz"

if [ ! -f "$ARCHIVE" ]; then
    echo "$ARCHIVE nicht gefunden." >&2
    exit 1
fi

# Ja/Nein-Rueckfrage; ohne Terminal (z.B. per Pipe) immer "nein".
ask() {
    [ -t 0 ] || return 1
    local answer
    read -rp "==> $1 [j/N] " answer
    case "$answer" in [jJyY]*) return 0 ;; *) echo "    Uebersprungen."; return 1 ;; esac
}

# Fehlende Pakete aus den Paketlisten nachinstallieren. Vor dem Einspielen
# der Config, damit Noctalia, hypr-persist, Cursor-Theme usw. schon da sind.
# Pakete, die es in den Repos nicht (mehr) gibt, werden uebersprungen statt
# die ganze Installation abzubrechen.
install_pkgs() {
    local repo="$SRC/pkglist-repo.txt" aur="$SRC/pkglist-aur.txt"
    if [ -s "$repo" ]; then
        local missing
        missing=$(comm -12 <(sort -u "$repo") <(pacman -Slq | sort -u) | comm -23 - <(pacman -Qq | sort -u))
        local unknown
        unknown=$(comm -23 <(sort -u "$repo") <(pacman -Slq | sort -u))
        [ -n "$unknown" ] && echo "    Nicht in den Repos, uebersprungen: $(echo $unknown)"
        if [ -n "$missing" ]; then
            echo "==> Installiere $(echo "$missing" | wc -l) Repo-Pakete"
            # shellcheck disable=SC2086
            sudo pacman -S --needed $missing
        else
            echo "==> Alle Repo-Pakete bereits installiert"
        fi
    fi
    if [ -s "$aur" ]; then
        local missing_aur
        missing_aur=$(comm -23 <(sort -u "$aur") <(pacman -Qq | sort -u))
        if [ -z "$missing_aur" ]; then
            echo "==> Alle AUR-Pakete bereits installiert"
        elif command -v paru >/dev/null; then
            # shellcheck disable=SC2086
            paru -S --needed $missing_aur
        elif command -v yay >/dev/null; then
            # shellcheck disable=SC2086
            yay -S --needed $missing_aur
        else
            echo "    Kein AUR-Helper (paru/yay) gefunden. Bitte manuell installieren:"
            echo "    $(echo $missing_aur)"
        fi
    fi
}

install_flatpaks() {
    local list="$SRC/flatpaks.txt"
    if ! command -v flatpak >/dev/null; then
        echo "    flatpak nicht installiert, uebersprungen."
        return
    fi
    local app origin inst
    while IFS=$'\t' read -r app origin inst; do
        [ -z "$app" ] && continue
        [ "$inst" = user ] && inst=--user || inst=--system
        # Standard-Remote flathub bei Bedarf anlegen; andere Remotes muessen
        # schon eingerichtet sein.
        if [ "$origin" = flathub ]; then
            flatpak remote-add "$inst" --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo
        fi
        if flatpak info "$inst" "$app" >/dev/null 2>&1; then
            echo "    $app bereits installiert"
        else
            flatpak install "$inst" -y "$origin" "$app" || echo "    Warnung: $app konnte nicht installiert werden." >&2
        fi
    done < "$list"
}

# Aktiviert die gesicherten Units, sofern es sie auf diesem System gibt und
# sie noch nicht aktiv sind. Nur "enable", kein "--now": Die Dienste starten
# beim naechsten Boot/Login, laufende Sitzung bleibt unberuehrt.
enable_units() {
    local scope="$1" list="$2" u state todo=() missing=()
    local -a sc=(systemctl)
    [ "$scope" = user ] && sc=(systemctl --user)
    while IFS= read -r u; do
        [ -z "$u" ] && continue
        state=$("${sc[@]}" is-enabled "$u" 2>/dev/null || true)
        case "$state" in
            enabled|enabled-runtime|static|alias|indirect) ;;
            "") missing+=("$u") ;;
            *) if "${sc[@]}" list-unit-files --no-legend "$u" 2>/dev/null | grep -q .; then
                   todo+=("$u")
               else
                   missing+=("$u")
               fi ;;
        esac
    done < "$list"
    [ "${#missing[@]}" -gt 0 ] && echo "    Nicht vorhanden (Paket fehlt?), uebersprungen: ${missing[*]}"
    if [ "${#todo[@]}" -eq 0 ]; then
        echo "    Alle $scope-Units bereits aktiviert."
        return
    fi
    echo "    Aktiviere ($scope): ${todo[*]}"
    if [ "$scope" = user ]; then
        "${sc[@]}" enable "${todo[@]}"
    else
        sudo systemctl enable "${todo[@]}"
    fi
}

if [ -s "$SRC/pkglist-repo.txt" ] || [ -s "$SRC/pkglist-aur.txt" ]; then
    ask "Fehlende Pakete aus den Paketlisten installieren?" && install_pkgs
fi

# Monitor-Layout (Ausgangsnamen, Positionen, Drehung) passt nur auf dieselbe
# Hardware. Ohne Wiederherstellung bleibt eine vorhandene monitors.lua
# unangetastet; fehlt sie, wird eine neutrale Standardregel angelegt, weil
# hyprland.lua sie per require() laedt.
MONITORS=".config/hypr/config/monitors.lua"
RESTORE_MONITORS=0
if tar -tzf "$ARCHIVE" "$MONITORS" >/dev/null 2>&1; then
    # Inhalt zeigen, damit man vor der Entscheidung sieht, welche Ausgaenge,
    # Positionen und Drehungen das Backup setzt -- nur bei Rueckfrage sinnvoll.
    if [ -t 0 ]; then
        echo "==> Gesicherte $MONITORS:"
        echo "------------------------------------------------------------"
        tar -xzOf "$ARCHIVE" "$MONITORS"
        echo "------------------------------------------------------------"
        # Zum Vergleich die Ausgaenge dieses Rechners (nur in laufendem Hyprland)
        if command -v hyprctl >/dev/null && hyprctl monitors all >/dev/null 2>&1; then
            echo "    Ausgaenge an diesem Rechner:"
            hyprctl monitors all | awk '
                /^Monitor /     { name = $2 }
                /description:/  { sub(/^[[:space:]]*description:[[:space:]]*/, ""); print "      " name "  (" $0 ")" }'
        fi
    fi
    ask "Monitor-Konfiguration wiederherstellen? (nur bei gleichen Monitoren/Anschluessen sinnvoll)" \
        && RESTORE_MONITORS=1
fi
TAR_EXCLUDE=()
[ "$RESTORE_MONITORS" -eq 1 ] || TAR_EXCLUDE=(--exclude="$MONITORS")

# Sicherheitsnetz: jede Datei, die das Archiv ueberschreiben wuerde, vorher
# wegsichern, damit ein Restore nichts unwiderruflich zerstoert. Die Liste
# kommt direkt aus dem Archiv und passt damit immer zu backup.sh.
SAFETY="$HOME/hypr-noctalia-backup-vor-restore-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$SAFETY"
while IFS= read -r p; do
    case "$p" in */) continue ;; esac
    [ "$RESTORE_MONITORS" -eq 1 ] || [ "$p" != "$MONITORS" ] || continue
    if [ -e "$HOME/$p" ]; then
        mkdir -p "$SAFETY/$(dirname "$p")"
        cp -a "$HOME/$p" "$SAFETY/$p"
    fi
done < <(tar -tzf "$ARCHIVE")
if [ -f "$SRC/dconf.ini" ] && command -v dconf >/dev/null; then
    dconf dump / > "$SAFETY/dconf.ini" 2>/dev/null || true
fi
echo "==> Aktueller Stand vorsorglich gesichert nach: $SAFETY"

echo "==> Spiele Hyprland- und Noctalia-Konfiguration ein"
tar -C "$HOME" -xzf "$ARCHIVE" "${TAR_EXCLUDE[@]}"

if [ "$RESTORE_MONITORS" -eq 0 ] && [ ! -e "$HOME/$MONITORS" ]; then
    cat > "$HOME/$MONITORS" <<'LUA'
-- Monitor-Konfiguration (beim Restore neutral angelegt)
-- Alle Monitore mit bevorzugter Aufloesung, automatisch nebeneinander.
-- Eigene Regeln pro Ausgang ergaenzen, Namen siehe: hyprctl monitors all
hl.monitor({
    output   = "",
    mode     = "preferred",
    position = "auto",
    scale    = 1.0,
})
LUA
    echo "    Neutrale monitors.lua angelegt (alle Monitore automatisch)."
elif [ "$RESTORE_MONITORS" -eq 0 ]; then
    echo "    Vorhandene monitors.lua beibehalten."
fi

if [ -f "$SRC/dconf.ini" ]; then
    if ! command -v dconf >/dev/null; then
        echo "    dconf nicht installiert, GTK/GNOME-Einstellungen uebersprungen."
    elif dconf load / < "$SRC/dconf.ini"; then
        echo "==> GTK/GNOME-Einstellungen (dconf) eingespielt"
    else
        echo "    Warnung: dconf load fehlgeschlagen (keine grafische Sitzung?)." >&2
        echo "    Spaeter nachholen: dconf load / < $SRC/dconf.ini" >&2
    fi
fi

if [ -s "$SRC/flatpaks.txt" ]; then
    ask "Flatpak-Apps installieren ($(wc -l < "$SRC/flatpaks.txt"))?" && install_flatpaks
fi

if [ -s "$SRC/services-system.txt" ] || [ -s "$SRC/services-user.txt" ]; then
    echo "    Achtung: Enthaelt hardwareabhaengige Dienste (z.B. nvidia-*, tlp)."
    if ask "Gesicherte systemd-Dienste aktivieren?"; then
        [ -s "$SRC/services-system.txt" ] && enable_units system "$SRC/services-system.txt"
        [ -s "$SRC/services-user.txt" ] && enable_units user "$SRC/services-user.txt"
    fi
fi

echo "==> Fertig."
echo "    Hyprland neu laden:      hyprctl reload"
echo "    Noctalia neu starten, damit die Einstellungen uebernommen werden."
[ "$RESTORE_MONITORS" -eq 1 ] && echo "    Monitore in ~/.config/hypr/config/monitors.lua ggf. an die Hardware anpassen."
echo "    UWSM-Umgebung und neu aktivierte Dienste greifen erst nach Neustart/Login."
