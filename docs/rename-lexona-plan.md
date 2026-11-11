# Rename to Lexona: plan (2026-11-11)

## Decision
The app is called **Lexona** (**L**inux **EX**perience **ON** **A**ndroid). Its subtitle, used
next to the name everywhere: **"Lexona – Linux desktop on Android"**.

Why Lexona:
- unique, with no collision in Linux/Android software;
- not tied to one device (phone, Fold, tablet, DeX/monitor);
- no "Droid…" prefix and no trademarks (DeX, Debian, Linux).

Known collisions that do not block it:
- Lexona s.r.o., Jablunkov (tool making);
- Lexona Ltd (UK);
- Lexona Ceramic (India);
- "LEXONA", an AI service for lawyers.

Fallback name: LinuShift. Rejected:
- Linexa (taken by a PLC/SCADA startup);
- Liona (Liona.ai, LIONA on Google Play);
- LinuDesk, LinuDock, LinuOne and others.

Identity rules: no "DeX", "Debian", "Droid" or the whole word "Linux" in the name or in
identifiers. The Linux Foundation wants a sublicence for product names containing "Linux".

## What changes

| Area | Now | After | Note |
|---|---|---|---|
| App name, label | DroidDesk | Lexona | `manifestPlaceholders["appLabel"]`, Flutter UI (about 80 strings) |
| applicationId | `com.orailnoor.droiddesk` | to be chosen after the domain check | new package = new app next to the old one |
| Kotlin namespace | `com.orailnoor.droiddesk` | stays for now | internal only; JNI symbol names in `cpp/*.c` and the prebuilt `libXlorie.so` are bound to it, renaming needs a rebuild of those |
| Commands | `droiddesk-*` (16 Termux, 8 Debian) | `lexona-*` | old names stay as links for one or two releases |
| Version | 1.0.1-fold.108 | 2.0.0 | versionCode keeps rising (110) |
| GitHub repo | Vyvrnc/DroidDesk-Fold | Vyvrnc/lexona (or an org) | GitHub redirects the old URL; Obtainium is told in the release notes |
| README | wrong install steps (Termux/X11) | rewritten for Lexona | with the subtitle, the acronym, credits to orailnoor/DroidDesk (GPL) |
| Icon, wallpaper, about | DroidDesk | Lexona | the mascot is still open |
| Runtime paths | `/data/user/0/com.orailnoor.droiddesk/...` | follow the new applicationId | the app derives paths from its own `filesDir`; fix hardcoded fallbacks in 4 assets (chromium-cam, firefox-cam, droiddesk-native-gpu, droiddesk-gpu-report) |

## Moving from DroidDesk to Lexona (new applicationId)
A new package cannot read the old app's data. Plan:
1. A last DroidDesk release gets **Export to Lexona**. It writes one archive to shared storage
   (Download/lexona-migration-<date>.tar):
   - Debian `/root` (projects, `~/.claude`, `~/.codex`, configs);
   - the Termux home;
   - `apt-mark showmanual` of Debian and Termux;
   - app settings (language, dock, zones, GPU opt-ins).
2. Lexona does a normal clean install (about 10 minutes). Then **Import from DroidDesk** unpacks
   the archive and reinstalls the extra packages from the lists.
3. Both apps can stay installed side by side until the user removes DroidDesk.

Not migrated: the Debian system itself (it is reinstalled; paths inside it would point at the
old package) and running sessions. Claude Code logs in again only if its credentials file is
not part of `~/.claude`; to be checked.

## Order
1. Check that the identifiers are free (GitHub, Play, F-Droid, domains). Choose the
   applicationId.
2. Name in UI, label, icon, about, subtitle. Version 2.0.0. Debug build `Lexona Dev`.
3. Commands `lexona-*` with the old names as links.
4. New applicationId and the hardcoded path fallbacks. Clean install test on the tablet.
5. Export (in DroidDesk) and import (in Lexona). Test on the tablet: DroidDesk with data, then
   Lexona next to it.
6. README rewrite, NOTICE/COMPLIANCE, repo rename, release 2.0.0 (on "vydej").
7. Later, separately: targetSdk 36 / Play Store, Kotlin namespace and JNI rename, mascot.
