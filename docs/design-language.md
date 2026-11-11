# Lexona design language

The rules every screen of the app, the desktop and the documentation follows. Colours,
sizes and styles come from `app/lib/theme/lexona_theme.dart`. A screen that needs a colour
or size not listed here adds it to the theme and to this document first.

## Identity
- **Name**: Lexona. **Subtitle**, always next to the name where there is room:
  "Lexona – Linux desktop on Android".
- **Mascot**: a teal chameleon. It changes colour and fits any screen: phone, foldable, tablet
  or monitor.
  - App icon: the chameleon on a monitor (`lexona-teal`).
  - Small places (notifications, themed icons): a one-colour silhouette.
  - The mascot is never recoloured, stretched or put on a busy photo, and it never says
    anything (no speech bubbles).
- **Voice**:
  - plain and specific: say what happens ("Installs Debian and XFCE, about 10 minutes");
  - no hype words ("blazing", "ultimate"), no exclamation marks except on "Setup complete!";
  - English in the app UI;
  - Czech texts (desktop scripts, notifications from Linux tools) with full diacritics.

## Colour

Dark is the default; light follows the same roles.

| Role | Dark | Light | Use |
|---|---|---|---|
| `background` | `#0B132B` ink | `#F5F9F8` | screen background |
| `surface` | `#111B36` | `#FFFFFF` | cards, sheets, dialogs, app bar |
| `surfaceRaised` | `#17233F` | `#EEF5F3` | icon tiles, inputs, selected rows |
| `border` | `#22304D` | `#D7E3E0` | 1 px card and divider lines |
| `primary` | `#14B8A6` teal | `#0D9488` | main action, active state, links, progress |
| `primarySoft` | `#5EEAD4` | `#0F766E` | text and icons on dark that need to be teal and readable |
| `onPrimary` | `#04211D` | `#FFFFFF` | text and icons on a teal fill |
| `accent` | `#FB7185` coral | `#E11D48` | rare highlight: new, the mascot, one call-out per screen |
| `success` | `#34D399` | `#059669` | done, tested, works |
| `warning` | `#FBBF24` | `#B45309` | works with limits, needs attention |
| `error` | `#F87171` | `#DC2626` | failed, broken, destructive action |
| `textPrimary` | `#EEF4FF` | `#0B132B` | titles, values |
| `textSecondary` | `#A7B4CC` | `#3D4B66` | body text |
| `textMuted` | `#7584A3` | `#5B6982` | captions, labels, hints |

Rules:
- **Teal means "this is the action or this is on".** Only one filled teal button per screen;
  other actions are outlined or text buttons.
- **Coral is spice.** At most one coral element per screen. It is never a status colour and
  never the error colour.
- **Every panel is opaque**: no translucent cards, dialogs, sheets or overlays over content.
  Tints (for example a teal icon tile) are solid colours from the table.
- Status always has an icon and a word as well as a colour (✓ works, ⚠ limits, ✗ broken,
  ? not tested, CPU/software), so it reads without colour too.
- Third-party colours (Claude orange, Codex, Firefox, distro logos) appear only inside that
  item's own icon tile, never as a button or a background.
- Contrast: body text at least 4.5:1 against its background, large text and icons at least 3:1.
  Teal fill takes dark text (`onPrimary`), not white.

## Type
- UI: **Inter**. Terminal output, commands, paths, versions, hashes: **JetBrains Mono**.

| Style | Size / weight | Use |
|---|---|---|
| `display` | 34 / 800, −1.0 | name on the welcome screen only |
| `title` | 24 / 700 | screen titles |
| `heading` | 18 / 600 | card and section headings |
| `subheading` | 15 / 600 | list row titles |
| `body` | 14 / 400, 1.5 | text |
| `caption` | 12 / 400 | secondary row text, notes |
| `label` | 11 / 600, +1.2, UPPERCASE | section labels ("QUICK ACTIONS") |
| `mono` | 13 / 400 | commands and values |
| `monoSmall` | 11 / 400 | log lines, hashes |

- Sentence case for titles and buttons ("Launch desktop", not "Launch Desktop").
- Numbers with units and a space ("7656 MB", "57 FPS").

## Space and shape
- 4 px grid: 4, 8, 12, 16, 24, 32, 48.
- Screen padding 24 (phone 16 when the width is under 400 dp). Between cards 12, inside a
  card 16, between sections 24.
- Radii: 8 for chips, inputs and small tiles; 12 for cards and buttons; 16 for dialogs and
  sheets; full for pills.
- Touch targets at least 48 × 48 dp; on DeX with a mouse the same sizes stay.
- No shadows on dark; separation by surface colour and a 1 px border.

## Components
- **Primary button**: teal fill, `onPrimary` text 15/600, radius 12, height 52, full width on
  setup screens. **Secondary**: 1 px teal outline, teal text. **Text button**: teal text.
  **Destructive**: error outline; error fill only in the confirmation dialog.
- **Card**: `surface`, 1 px `border`, radius 12, padding 16.
- **Action row** (home screen): 40 × 40 icon tile (`surfaceRaised`, icon in the item's colour),
  title `subheading`, one line `caption`, chevron in `textMuted`. The whole row is the target.
- **Info row**: label left (`caption`), value right (`mono` or `body`); tappable rows end with
  a chevron.
- **Status row** (GPU support and similar): status icon 20, title, detail, evidence line in
  `caption` `textMuted`.
- **Section label**: `label` style above a group, 24 above, 8 below.
- **Progress**: teal ring or bar on `surfaceRaised`; the current step names what happens.
- **Dialogs**: opaque `surface`, radius 16, title `heading`, at most two actions, the safe one
  on the left.
- **Terminal / log view**: `background` colour, `monoSmall`, `textSecondary`; errors in `error`.

## Icons
- Material Symbols, rounded, 24 in rows and 20 in status lines. A filled icon means "active"
  or "selected".
- The app icon and the mascot come from `assets/brand/` (generated from the `lexona-teal` set).

## Motion
- 150–250 ms for state changes (fade, colour); 300–400 ms for entering screens
  (fade + 8 px slide). No bounce or elastic effects, except the single success check at the end
  of the setup.
- Nothing moves on its own while the user reads; progress indicators are the only loops.

## Desktop side
- Wallpaper: `lexona-teal-wallpaper` (ink with a teal glow, small chameleon bottom right).
- XFCE stays on Fluent; its accent follows teal where the theme allows (Fluent's teal variant).

## Checklist for a new or changed screen
1. Colours, type and sizes come from the theme.
2. One filled teal button at most.
3. At most one coral element.
4. Status has an icon and a word.
5. Nothing translucent.
6. Sentence case.
7. Targets at least 48 dp.
8. Works in dark and light.
9. Checked on the phone screen and on DeX.
