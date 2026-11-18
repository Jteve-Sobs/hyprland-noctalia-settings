# hyprland-noctalia-settings

Backup meiner Desktop-Umgebung (CachyOS + Hyprland + Noctalia), damit sich ein
neues System mit wenigen Befehlen genauso einrichten lässt.

## Inhalt

| Datei | Inhalt |
|---|---|
| `hypr-noctalia-config.tar.gz` | Konfigurationsdateien relativ zu `$HOME` (Liste siehe unten) |
| `pkglist-repo.txt` | Explizit installierte Repo-Pakete (`pacman -Qqen`) |
| `pkglist-aur.txt` | Explizit installierte AUR-/Fremdpakete (`pacman -Qqem`) |
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
- **Shell und Terminal:** `fish`, `kitty`, `hyfetch`/`fastfetch`
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

Das Skript fragt jeden größeren Schritt einzeln ab (`j` = ja, Enter = nein):

1. **Pakete:** Fehlende Repo-Pakete werden mit `pacman` installiert, AUR-Pakete
   mit `paru` (oder `yay`). Pakete, die es in den Repos nicht mehr gibt, werden
   übersprungen.
2. **Monitore:** Zeigt die gesicherte `monitors.lua` und die Anschlüsse des
   neuen Rechners. Nur übernehmen, wenn Monitore und Anschlüsse gleich sind.
   Sonst bleibt eine vorhandene `monitors.lua` erhalten, oder es wird eine
   neutrale angelegt (alle Monitore automatisch).
3. **Sicherheitskopie:** Jede Datei, die überschrieben würde, wird vorher nach
   `~/hypr-noctalia-backup-vor-restore-<Datum>` kopiert.
4. **Config einspielen:** Entpackt das Archiv nach `$HOME`. Der Hyprland-
   Autoreload ist währenddessen pausiert. Danach wird einmal neu geladen und
   `hyprctl configerrors` geprüft.
5. **dconf:** Lädt `dconf.ini`.
6. **Flatpaks:** Installiert die Apps aus `flatpaks.txt`. Flathub wird bei
   Bedarf angelegt, andere Remotes müssen schon eingerichtet sein.
7. **Dienste:** Aktiviert die gesicherten Units nur mit `enable`, sie starten
   also erst beim nächsten Boot oder Login.

> **Achtung:** Die Dienstlisten enthalten hardwareabhängige Units (z.B.
> `nvidia-*`, `tlp`). Auf anderer Hardware die Listen vorher prüfen oder
> diesen Schritt überspringen.

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

Neue Pfade fügt man in `backup.sh` im Array `CONFIG_PATHS` hinzu. `restore.sh`
muss dafür nicht angepasst werden, weil es die Dateiliste direkt aus dem
Archiv liest.

## Hinweise

- Das Archiv ist ungefähr 8 MB groß, das meiste davon sind Hintergrundbilder.
- `restore.sh` lässt sich gefahrlos mehrfach ausführen. Bereits installierte
  Pakete, Flatpaks und aktive Dienste werden übersprungen.
