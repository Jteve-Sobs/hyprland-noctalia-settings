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
# ask        -> Standard nein [j/N], Enter ueberspringt
# ask_yes    -> Standard ja   [J/n], Enter fuehrt aus
ask() {
    [ -t 0 ] || return 1
    local answer
    read -rp "==> $1 [j/N] " answer
    case "$answer" in [jJyY]*) return 0 ;; *) echo "    Uebersprungen."; return 1 ;; esac
}
ask_yes() {
    [ -t 0 ] || return 1
    local answer
    read -rp "==> $1 [J/n] " answer
    case "$answer" in [nN]*) echo "    Uebersprungen."; return 1 ;; *) return 0 ;; esac
}

# Optionale Paketgruppen (pkglist-optional.txt): hardwareabhaengige Pakete wie
# NVIDIA-Treiber oder tlp. Sie werden aus den normalen Listen herausgefiltert
# und nur installiert (bzw. ihre Dienste aktiviert), wenn man die Gruppe
# ausdruecklich auswaehlt.
OPT_FILE="$SRC/pkglist-optional.txt"
OPT_GROUPS=()
declare -A OPT_DESC=() OPT_DETECT=() OPT_PKGS=() OPT_SVCS=()
OPT_ALL_PKGS="" OPT_ALL_SVCS=""   # alle optionalen Pakete/Units
SEL_PKGS="" SEL_SVCS=""           # davon ausgewaehlt

parse_optional() {
    [ -f "$OPT_FILE" ] || return 0
    local line g=""
    while IFS= read -r line || [ -n "$line" ]; do
        line="${line#"${line%%[![:space:]]*}"}"
        [[ -z "$line" || "$line" == \#* ]] && continue
        if [[ "$line" =~ ^\[([^]]+)\][[:space:]]*(.*)$ ]]; then
            g="${BASH_REMATCH[1]}"
            OPT_GROUPS+=("$g")
            OPT_DESC[$g]="${BASH_REMATCH[2]}"
        elif [ -z "$g" ]; then
            continue
        elif [[ "$line" == detect:* ]]; then
            OPT_DETECT[$g]="${line#detect:}"
        elif [[ "$line" == service:* ]]; then
            OPT_SVCS[$g]+=" ${line#service:}"
            OPT_ALL_SVCS+=" ${line#service:}"
        else
            OPT_PKGS[$g]+=" $line"
            OPT_ALL_PKGS+=" $line"
        fi
    done < "$OPT_FILE"
}

# Wortliste -> sortierte Zeilenliste (fuer comm)
words_to_lines() { printf '%s\n' $1 | grep -v '^$' | sort -u || true; }

select_optional() {
    [ "${#OPT_GROUPS[@]}" -gt 0 ] || return 0
    echo "==> Optionale Paketgruppen (hardwareabhaengig, Standard: nein)"
    local g hint
    for g in "${OPT_GROUPS[@]}"; do
        hint=""
        if [ -n "${OPT_DETECT[$g]:-}" ]; then
            if bash -c "${OPT_DETECT[$g]}" >/dev/null 2>&1; then
                hint=" [auf diesem Rechner erkannt]"
            else
                hint=" [nicht erkannt]"
            fi
        fi
        echo "    Pakete:$(echo ${OPT_PKGS[$g]:-})${OPT_SVCS[$g]:+  | Dienste: $(echo ${OPT_SVCS[$g]})}"
        if ask "${OPT_DESC[$g]:-$g} installieren?$hint"; then
            SEL_PKGS+=" ${OPT_PKGS[$g]:-}"
            SEL_SVCS+=" ${OPT_SVCS[$g]:-}"
        fi
    done
}

# Fehlende Pakete aus den Paketlisten nachinstallieren. Vor dem Einspielen
# der Config, damit Noctalia, hypr-persist, Cursor-Theme usw. schon da sind.
# Pakete, die es in den Repos nicht (mehr) gibt, werden uebersprungen statt
# die ganze Installation abzubrechen. Optionale Pakete kommen nur mit, wenn
# ihre Gruppe ausgewaehlt wurde.
install_pkgs() {
    local repo="$SRC/pkglist-repo.txt" aur="$SRC/pkglist-aur.txt"
    # Erst Paketdatenbanken holen und System aktualisieren. Ohne -y kennt
    # pacman nur die alten Versionen, die auf den Mirrors schon geloescht sind
    # (404 auf allen Mirrors). Nur -Sy ohne -u wuerde ein Teil-Update erzeugen,
    # das auf Arch nicht unterstuetzt ist -- daher immer -Syu.
    echo "==> Aktualisiere Paketdatenbanken und System (pacman -Syu)"
    if ! sudo pacman -Syu; then
        echo "    Fehler: Systemupdate fehlgeschlagen, Pakete werden nicht installiert." >&2
        echo "    Mirrors pruefen (sudo cachyos-rate-mirrors) und restore.sh erneut starten." >&2
        return 0
    fi
    local synced installed opt sel
    synced=$(pacman -Slq | sort -u)
    installed=$(pacman -Qq | sort -u)
    opt=$(words_to_lines "$OPT_ALL_PKGS")
    sel=$(words_to_lines "$SEL_PKGS")

    # Gewuenschte Listen: Basislisten ohne optionale Pakete, plus die
    # ausgewaehlten optionalen (je nachdem, ob im Repo oder im AUR).
    local want_repo="" want_aur=""
    [ -f "$repo" ] && want_repo=$(sort -u "$repo" | comm -23 - <(echo "$opt"))
    [ -f "$aur" ] && want_aur=$(sort -u "$aur" | comm -23 - <(echo "$opt"))
    want_repo=$(printf '%s\n%s\n' "$want_repo" "$(comm -12 <(echo "$sel") <(echo "$synced"))" | grep -v '^$' | sort -u || true)
    want_aur=$(printf '%s\n%s\n' "$want_aur" "$(comm -23 <(echo "$sel") <(echo "$synced"))" | grep -v '^$' | sort -u || true)

    local skipped
    skipped=$(comm -23 <(echo "$opt") <(echo "$sel") | grep -v '^$' || true)
    [ -n "$skipped" ] && echo "    Optional, nicht ausgewaehlt: $(echo $skipped)"

    if [ -n "$want_repo" ]; then
        local missing unknown
        missing=$(comm -12 <(echo "$want_repo") <(echo "$synced") | comm -23 - <(echo "$installed"))
        unknown=$(comm -23 <(echo "$want_repo") <(echo "$synced"))
        [ -n "$unknown" ] && echo "    Nicht in den Repos, uebersprungen: $(echo $unknown)"
        if [ -n "$missing" ]; then
            echo "==> Installiere $(echo "$missing" | wc -l) Repo-Pakete"
            # shellcheck disable=SC2086
            sudo pacman -S --needed $missing
        else
            echo "==> Alle Repo-Pakete bereits installiert"
        fi
    fi
    if [ -n "$want_aur" ]; then
        local missing_aur
        missing_aur=$(comm -23 <(echo "$want_aur") <(echo "$installed"))
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
    local -a optout=() dmskip=() failed=()
    while IFS= read -r u; do
        [ -z "$u" ] && continue
        # Dienst einer optionalen Gruppe, die nicht ausgewaehlt wurde
        if [[ " $OPT_ALL_SVCS " == *" $u "* && " $SEL_SVCS " != *" $u "* ]]; then
            optout+=("$u")
            continue
        fi
        # Login-Manager (Alias=display-manager.service): Es kann nur einen
        # geben. Ist auf diesem System schon ein anderer aktiv (z.B. greetd),
        # nicht umstellen -- systemctl enable wuerde sonst scheitern.
        if [ "$scope" = system ] \
            && "${sc[@]}" cat "$u" 2>/dev/null | grep -qx 'Alias=display-manager.service'; then
            local dm
            dm=$(readlink /etc/systemd/system/display-manager.service 2>/dev/null || true)
            if [ -n "$dm" ] && [ "$(basename "$dm")" != "$u" ]; then
                dmskip+=("$u (aktiv: $(basename "$dm"))")
                continue
            fi
        fi
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
    [ "${#optout[@]}" -gt 0 ] && echo "    Optional, nicht ausgewaehlt: ${optout[*]}"
    [ "${#dmskip[@]}" -gt 0 ] && echo "    Anderer Login-Manager bereits aktiv, uebersprungen: ${dmskip[*]}"
    [ "${#missing[@]}" -gt 0 ] && echo "    Nicht vorhanden (Paket fehlt?), uebersprungen: ${missing[*]}"
    if [ "${#todo[@]}" -eq 0 ]; then
        echo "    Alle $scope-Units bereits aktiviert."
        return
    fi
    echo "    Aktiviere ($scope): ${todo[*]}"
    # Einzeln aktivieren: Scheitert eine Unit, laufen die anderen trotzdem
    # und das Skript bricht nicht ab (set -e).
    for u in "${todo[@]}"; do
        if [ "$scope" = user ]; then
            "${sc[@]}" enable "$u" || failed+=("$u")
        else
            sudo systemctl enable "$u" || failed+=("$u")
        fi
    done
    [ "${#failed[@]}" -gt 0 ] && echo "    Warnung: Konnte nicht aktiviert werden: ${failed[*]}" >&2
    return 0
}

# Mirrorlisten zuerst neu bewerten: Auf frischen Systemen stehen oft veraltete
# oder kaputte Mirrors oben (404 auf .sig-Dateien), dann scheitert jede
# Paketinstallation.
if command -v cachyos-rate-mirrors >/dev/null; then
    if ask_yes "Paket-Mirrors neu bewerten (cachyos-rate-mirrors, dauert ca. 1 Minute)?"; then
        sudo cachyos-rate-mirrors \
            || echo "    Warnung: cachyos-rate-mirrors fehlgeschlagen, fahre mit bestehenden Mirrors fort." >&2
    fi
else
    echo "    cachyos-rate-mirrors nicht gefunden, Mirrors bleiben unveraendert."
fi

# Immer einlesen: auch wenn der Paketschritt uebersprungen wird, sollen die
# Dienste nicht ausgewaehlter optionaler Gruppen nicht aktiviert werden.
parse_optional

if [ -s "$SRC/pkglist-repo.txt" ] || [ -s "$SRC/pkglist-aur.txt" ]; then
    if ask_yes "System aktualisieren und fehlende Pakete aus den Paketlisten installieren?"; then
        # Alle Fragen vor dem langen Update stellen, danach laeuft es durch
        select_optional
        install_pkgs
    fi
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

# Hyprland laedt die Config bei jeder Dateiaenderung automatisch neu. tar
# schreibt die Dateien nacheinander -- ein Reload mitten im Entpacken sieht
# eine halb eingespielte Config, scheitert und schaltet auf die Notfall-
# Keybinds. Daher Autoreload waehrend des Einspielens aus und danach genau
# einmal gezielt neu laden. Der trap schaltet ihn auch bei Abbruch wieder ein.
HYPR_LIVE=0
if [ -n "${HYPRLAND_INSTANCE_SIGNATURE:-}" ] && command -v hyprctl >/dev/null \
    && hyprctl eval 'hl.config({ misc = { disable_autoreload = true } })' >/dev/null 2>&1; then
    HYPR_LIVE=1
    trap 'hyprctl eval "hl.config({ misc = { disable_autoreload = false } })" >/dev/null 2>&1 || true' EXIT
    echo "    Hyprland-Autoreload waehrend des Einspielens pausiert."
fi

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

if [ "$HYPR_LIVE" -eq 1 ]; then
    hyprctl reload >/dev/null
    hyprctl eval 'hl.config({ misc = { disable_autoreload = false } })' >/dev/null 2>&1 || true
    trap - EXIT
    ERRS=$(hyprctl configerrors 2>/dev/null | grep -v '^[[:space:]]*$' || true)
    if [ -n "$ERRS" ]; then
        echo "    Warnung: Hyprland meldet Config-Fehler:" >&2
        echo "$ERRS" | sed 's/^/      /' >&2
    else
        echo "==> Hyprland-Config neu geladen, keine Fehler"
    fi
fi

# Noctalia-Widgets (Sperrbildschirm-Uhr, Desktop-Widgets) sind an einen Monitor
# gebunden (output = "eDP-1"). Gibt es diesen Monitor hier nicht (VM, anderer
# PC), zeigt Noctalia das Widget gar nicht an. Bei leerem output nimmt Noctalia
# den ersten Monitor, traegt dessen Namen ein und skaliert die Position auf
# dessen Aufloesung. Login-Boxen (lockscreen-login-box@...) legt Noctalia pro
# Monitor selbst an (inkl. FALLBACK), die bleiben unveraendert.
NOCTALIA_SETTINGS="$HOME/.local/state/noctalia/settings.toml"
if [ "$HYPR_LIVE" -eq 1 ] && [ -f "$NOCTALIA_SETTINGS" ] && command -v python3 >/dev/null; then
    hyprctl monitors all -j 2>/dev/null | python3 -c '
import json, re, sys
path = sys.argv[1]
mons = json.load(sys.stdin)
names = {m.get("name", "") for m in mons}
descs = [m.get("description", "") for m in mons]
def present(sel):
    return sel in names or any(sel and sel in d for d in descs)
sec_re = re.compile(r"^\s*\[(lockscreen|desktop)_widgets\.widget\.\"?([^\]\"]+)\"?\]\s*$")
out_re = re.compile(r"^(\s*output\s*=\s*)\"([^\"]*)\"(\s*)$")
lines = open(path, encoding="utf-8").read().split("\n")
cur, moved = None, []
for i, line in enumerate(lines):
    if line.lstrip().startswith("["):
        m = sec_re.match(line)
        cur = m.group(2) if m and not m.group(2).startswith("lockscreen-login-box@") else None
        continue
    if cur:
        m = out_re.match(line)
        if m and m.group(2) and not present(m.group(2)):
            lines[i] = m.group(1) + "\"\"" + m.group(3)
            moved.append(f"{cur} ({m.group(2)})")
if moved:
    open(path, "w", encoding="utf-8").write("\n".join(lines))
    print("==> Noctalia-Widgets auf den ersten Monitor verschoben (gesicherter Monitor fehlt hier):")
    for w in moved:
        print("      " + w)
' "$NOCTALIA_SETTINGS" || echo "    Warnung: Noctalia-Widgets konnten nicht an die Monitore angepasst werden." >&2
fi

# Cursor-Theme pruefen: Die Config verweist nur auf den Namen, das Theme selbst
# kommt aus dem AUR-Paket bibata-cursor-theme-bin. Fehlt es (z.B. weil die
# Paketinstallation uebersprungen wurde oder fehlschlug), zeigt Hyprland nur den
# Standard-Cursor.
CURSOR_THEME="Bibata-Modern-Classic"
if [ -d "/usr/share/icons/$CURSOR_THEME" ] || [ -d "$HOME/.local/share/icons/$CURSOR_THEME" ]; then
    if [ "$HYPR_LIVE" -eq 1 ]; then
        hyprctl setcursor "$CURSOR_THEME" 24 >/dev/null 2>&1 || true
        echo "==> Cursor $CURSOR_THEME aktiviert"
    fi
else
    echo "    Warnung: Cursor-Theme $CURSOR_THEME ist nicht installiert." >&2
    echo "    Nachinstallieren: paru -S bibata-cursor-theme-bin  (danach neu anmelden)" >&2
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
    echo "    Dienste optionaler Gruppen (nvidia-*, tlp ...) nur, wenn die Gruppe ausgewaehlt wurde."
    if ask "Gesicherte systemd-Dienste aktivieren?"; then
        [ -s "$SRC/services-system.txt" ] && enable_units system "$SRC/services-system.txt"
        [ -s "$SRC/services-user.txt" ] && enable_units user "$SRC/services-user.txt"
    fi
fi

echo "==> Fertig."
[ "$HYPR_LIVE" -eq 1 ] || echo "    Hyprland neu laden:      hyprctl reload"
echo "    Noctalia neu starten, damit die Einstellungen uebernommen werden."
[ "$RESTORE_MONITORS" -eq 1 ] && echo "    Monitore in ~/.config/hypr/config/monitors.lua ggf. an die Hardware anpassen."
echo "    UWSM-Umgebung und neu aktivierte Dienste greifen erst nach Neustart/Login."
