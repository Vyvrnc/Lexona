# webapp-icons

Sharp panel icons and a window class of their own for web apps started with Chromium `--app`.
A manual setup from the Galaxy Z Fold 7 (2026-11-19), not part of the APK yet. The plan is an
"Add web app" function in Lexona that ships this daemon (Gitea issue #6).

## Pieces on the Fold

- `x11-seticon.py` in `~/.local/bin/`, started from autostart ("Web app icons"):
  `Exec=<PREFIX>/usr/bin/debian-run /usr/bin/python3 <HOME>/.local/bin/x11-seticon.py --config <HOME>/.config/webapp-icons.conf`
- Configuration `~/.config/webapp-icons.conf`, see `webapp-icons.conf.example`.
- Debian packages: `python3-xlib`, `python3-pil`, `fonts-dejavu-core`.
- Icons: Papirus `64x64/apps` SVG rendered with `rsvg-convert -w 256 -h 256` into
  `~/.local/share/icons/webapps/` (gmail, google-agenda as google-calendar, google-drive,
  google-meet, slack, element). Claude uses `hicolor/scalable/apps/claude-code.svg`.
- Launcher `~/.local/bin/chromium-webapp URL`:
  `CHROMIUM_CAM_PROFILE=$HOME/.config/chromium-google exec chromium-cam --app URL`

## Known limits

- python-xlib has no BIG-REQUESTS: a 256 px icon goes over the request limit, so sizes stop at 128 px.

Verified on the Fold on 2026-11-19: Claude and Slack windows get 16–128 px icons and their own
class, the Gmail badge works after signing in.
