# hyprland-noctalia-settings

Backup meiner Desktop-Umgebung (CachyOS + Hyprland + Noctalia), damit sich ein
neues System mit wenigen Befehlen genauso einrichten lässt.

## Inhalt

| Datei | Inhalt |
|---|---|
| `hypr-noctalia-config.tar.gz` | Konfigurationsdateien relativ zu `$HOME` (Liste siehe unten) |
| `pkglist-repo.txt` | Explizit installierte Repo-Pakete (`pacman -Qqen`) |
| `pkglist-aur.txt` | Explizit installierte AUR-/Fremdpakete (`pacman -Qqem`) |
| `pkglist-optional.txt` | Hardwareabhängige Paketgruppen (NVIDIA, Intel, tlp, VM …), nur nach Rückfrage. Von Hand gepflegt |
| `flatpaks.txt` | Flatpak-Apps: App-ID, Remote, Installation (system/user) |
| `services-system.txt` | Aktivierte systemd-Units (System) |
| `services-user.txt` | Aktivierte systemd-Units (Benutzer) |
| `dconf.ini` | GTK/GNOME-Einstellungen als Text-Dump (`dconf dump /`) |
| `backup.sh` | Erstellt alle Dateien oben neu |
| `restore.sh` | Spielt das Backup auf einem System ein |

Im Archiv gesichert:

- **Hyprland:** `~/.config/hypr` (Lua-Config, Skripte, `xdph.conf`)
- **Noctalia:** `~/.config/noctalia` sowie `settings.toml`, `state.toml` und
  Plugin-Daten aus `~/.local/state/noctalia`
- **Hintergrundbilder:** der Rotationsordner und die einzeln gesetzten Bilder
  aus den Noctalia-Einstellungen, z.B. `~/Bilder/Hintergrundbilder`
- **Fensteranordnung beim Start:** `~/.local/share/hypr-persist/sessions`
  (wird beim Autostart mit `hypr-persist restore startup` geladen)
- **Umgebung und Theming:** `~/.config/uwsm`, `qt5ct`, `qt6ct`, `gtk-3.0`,
  `gtk-4.0`, `kcminputrc`, Standard-Cursor
- **Shell und Terminal:** `fish`, `alacritty`, `kitty`, `hyfetch`/`fastfetch`,
  `xdg-terminals.list` (Standard-Terminal, z.B. für den arch-update-Tray)
- **Standard-Apps:** `mimeapps.list`, `makemkv.desktop`

Nicht gesichert werden Cache, Verläufe (Zwischenablage, Benachrichtigungen),
Passwörter und Schlüssel.

## Neues System einrichten

### 1. Voraussetzungen

- CachyOS installieren, am besten gleich mit der Hyprland/Noctalia-Edition
  (Paket `cachyos-hypr-noctalia`). Ein anderes Arch-System geht auch, dann
  müssen aber die CachyOS-Repos eingebunden sein, sonst fehlen einige Pakete.
- Benutzer anlegen und einmal grafisch anmelden.
- `git` installieren: `sudo pacman -S --needed git`

### 2. Repo klonen

```bash
mkdir -p ~/Dokumente/GitHub
git clone https://github.com/Jteve-Sobs/hyprland-noctalia-settings.git ~/Dokumente/GitHub/hyprland-noctalia-settings
cd ~/Dokumente/GitHub/hyprland-noctalia-settings
```

### 3. Restore ausführen

Am besten aus einem Terminal **innerhalb einer laufenden Hyprland-Sitzung**:

```bash
./restore.sh
```

Das Skript fragt jeden größeren Schritt einzeln ab. Bei Mirrors und Paketen
ist Ja voreingestellt (`[J/n]`, Enter = ja), bei allen anderen Schritten Nein
(`[j/N]`, Enter = nein):

0. **Mirrors:** Zuerst bewertet `sudo cachyos-rate-mirrors` die Paket-Mirrors
   neu. Auf frischen Systemen stehen sonst oft veraltete
   Mirrors oben, und pacman scheitert mit 404-Fehlern.
1. **Pakete:** Zuerst fragt das Skript jede Gruppe aus `pkglist-optional.txt`
   einzeln ab (`[j/N]`) und zeigt dabei, ob die Hardware auf diesem Rechner
   erkannt wurde. Danach aktualisiert `sudo pacman -Syu` die Paketdatenbanken
   und das System. Anschließend werden fehlende Repo-Pakete mit `pacman`
   installiert, AUR-Pakete mit `paru` (oder `yay`). Optionale Pakete kommen nur
   mit, wenn ihre Gruppe ausgewählt wurde. Pakete, die es in den Repos nicht
   mehr gibt, werden übersprungen.
2. **Monitore:** Zeigt die gesicherte `monitors.lua` und die Anschlüsse des
   neuen Rechners. Nur übernehmen, wenn Monitore und Anschlüsse gleich sind.
   Sonst bleibt eine vorhandene `monitors.lua` erhalten, oder es wird eine
   neutrale angelegt (alle Monitore automatisch).
3. **Sicherheitskopie:** Jede Datei, die überschrieben würde, wird vorher nach
   `~/hypr-noctalia-backup-vor-restore-<Datum>` kopiert.
4. **Config einspielen:** Entpackt das Archiv nach `$HOME`. Der Hyprland-
   Autoreload ist währenddessen pausiert. Danach wird einmal neu geladen und
   `hyprctl configerrors` geprüft.
   Noctalia-Widgets (Sperrbildschirm-Uhr, Desktop-Widgets), deren Monitor es
   auf diesem Rechner nicht gibt, werden auf den ersten Monitor verschoben.
   Sonst wären sie unsichtbar, z.B. in einer VM ohne `eDP-1`.
5. **dconf:** Lädt `dconf.ini`.
6. **Flatpaks:** Installiert die Apps aus `flatpaks.txt`. Flathub wird bei
   Bedarf angelegt, andere Remotes müssen schon eingerichtet sein.
7. **Dienste:** Aktiviert die gesicherten Units nur mit `enable`, sie starten
   also erst beim nächsten Boot oder Login.

   Dienste aus optionalen Gruppen (z.B. `nvidia-*`, `tlp`) werden nur
   aktiviert, wenn ihre Gruppe beim Paketschritt ausgewählt wurde.

### 4. Danach

- Abmelden und neu anmelden oder neu starten. Erst dann greifen die
  UWSM-Umgebung (Cursor, Qt-Theme), die Dienste und die Fensteranordnung.
- Noctalia neu starten, falls es schon lief.
- Bei anderer Hardware die Monitore in `~/.config/hypr/config/monitors.lua`
  anpassen. Die Namen der Ausgänge zeigt `hyprctl monitors all`.
- Die Shell auf fish umstellen, falls das noch nicht so ist: `chsh -s /usr/bin/fish`
- Noctalia-Plugins kommen aus ihrem Plugin-Repo. Gesichert sind nur ihre Daten
  und Einstellungen, die Plugins also über Noctalia neu installieren.

## Backup aktualisieren

Nach Änderungen an der Config auf dem aktuellen Rechner:

```bash
cd ~/Dokumente/GitHub/hyprland-noctalia-settings
./backup.sh
git add -A && git commit -m "Neue Sicherung" && git push
```

`backup.sh` erzeugt das Archiv, die Paket-, Dienst- und Flatpak-Listen sowie
`dconf.ini` neu und listet am Ende alle gesicherten Pfade auf.

`pkglist-optional.txt` ändert `backup.sh` nicht. Kommt auf dem Laptop ein
neues hardwareabhängiges Paket dazu, trägt man es dort von Hand in die passende
Gruppe ein (oder legt mit `[name] Beschreibung` eine neue Gruppe an).

Neue Pfade fügt man in `backup.sh` im Array `CONFIG_PATHS` hinzu. `restore.sh`
muss dafür nicht angepasst werden, weil es die Dateiliste direkt aus dem
Archiv liest.

## Hinweise

- Das Archiv ist ungefähr 8 MB groß, das meiste davon sind Hintergrundbilder.
- `restore.sh` lässt sich gefahrlos mehrfach ausführen. Bereits installierte
  Pakete, Flatpaks und aktive Dienste werden übersprungen.
