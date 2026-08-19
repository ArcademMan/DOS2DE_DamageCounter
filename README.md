<p align="center">
  <img src="./assets/icon.png" alt="DamageCounter" width="180">
</p>

<h1 align="center">DamageCounter</h1>

<p align="center">
  <strong>Combat statistics tracker for Divinity: Original Sin 2 — Definitive Edition</strong><br>
  Per-character damage, kills, healing and per-spell breakdowns — live web dashboard, in-game panel, desktop app.
</p>

<p align="center">
  <img src="https://img.shields.io/badge/platform-Windows-blue" alt="Platform">
  <img src="https://img.shields.io/badge/game-DOS2%20DE-red" alt="DOS2 DE">
  <img src="https://img.shields.io/badge/mod-Script%20Extender%20(Lua)-orange" alt="Script Extender">
  <img src="https://img.shields.io/badge/backend-FastAPI-brown" alt="FastAPI">
  <img src="https://img.shields.io/badge/frontend-Vue%203-green" alt="Vue">
  <img src="https://img.shields.io/badge/license-MIT-lightgrey" alt="License">
</p>

---

See **who is actually carrying your party**, in real time. A Script Extender mod
tracks every hit, kill, death and heal per character (summons credited to their
owner, friendly fire kept separate), exports the numbers to JSON, and a local
web app turns them into a leaderboard you can keep on a second monitor or share
on stream. No dependencies on other mods — no LeaderLib, no Epip.

## Features

| Part | Description |
|------|-------------|
| **Mod (Lua)** | 40+ per-character stats: damage dealt/taken, crits, kills, deaths, skill/surface/status damage, reflected damage, friendly fire, self-damage, vitality healing done/received, biggest hit. Summon damage credited to the owner. Stats live in the savegame (`PersistentVars`): reloading a save rewinds the numbers with it |
| **Per-spell tracking** | Every skill a character uses: casts, hits, total damage, crits, crit damage, biggest hit — with the real in-game skill icons |
| **Web dashboard** | Dark-themed leaderboard (Vue 3, polling 1s): ranking cards with damage share bars, full stat table with per-row leader highlight |
| **Spells page** | `/spells` — per-character spell breakdown, character switcher, shareable URL |
| **In-game panel** | Press **F7** in game: the full scoreboard in a native game window (vanilla `msgBox.swf`, no UI mods required) |
| **Desktop app** | Native dark window (PySide6 + embedded Chromium) that runs the server internally: no terminal, no browser. Settings dialog for stats file path and port |
| **Console tools** | `!export`, `!stats`, `!dcprobe` (event/listener diagnostics), `!hitlog` (per-hit log), `!reset_stats` and more |

## Repository layout

```
mod/DamageCounter_<uuid>/   the game mod (Script Extender Lua + meta)
app.py                      FastAPI server: /api/stats, /api/icon/<name>, pages
desktop.py                  desktop app: Qt window + internal server + settings
static/                     leaderboard + spells pages (Vue 3, dark theme)
tools/build_icon_index.py   builds the skill-icon index from extracted atlases
tools/make_icon.py          generates the project icon
DamageCounter.spec          PyInstaller build for the desktop exe
```

## Installation

### Mod

1. Install [Norbyte's Script Extender](https://github.com/Norbyte/ositools).
2. Subscribe to [DamageCounter on the Steam Workshop](https://steamcommunity.com/sharedfiles/filedetails/?id=3786442402)
   — Steam downloads the `.pak` for you.
3. Enable **DamageCounter** in the in-game mod manager and load a save.

(Manual alternative: build the `.pak` from `mod/DamageCounter_<uuid>/` with
the Divinity Engine 2 and drop it into
`Documents\Larian Studios\Divinity Original Sin 2 Definitive Edition\Mods\`.)

### Dashboard

```bash
pip install -r requirements.txt
python desktop.py        # desktop app (needs: pip install PySide6)
# or:
python app.py            # server only, then open http://127.0.0.1:48124
```

In game, open the Script Extender console and run `!export` once — from then
on the export refreshes itself (at most every 2 s, only when something changed).

### Skill icons (optional)

Icons are cropped from the game's own texture atlases, which are copyrighted
Larian assets and therefore **not redistributed** with this repository or with
the exe. If you extract them yourself, just drop them in the right folder and
everything lights up on its own:

1. Extract `Shared.pak` (from `...\Divinity Original Sin 2\DefEd\Data\`) with
   [divine.exe (LSLib)](https://github.com/Norbyte/lslib). The files that
   matter are the atlas pairs: `Public/Shared/GUI/*.lsx` +
   `Public/Shared/Assets/Textures/Icons/*.dds`. Paks of other installed mods
   can be added the same way for their custom skill icons.
2. Put the extracted files into an `icon_assets/` folder **next to the exe**
   (or in the repository root if you run from source). Any layout works — the
   folder is scanned recursively.
3. Restart the app. On startup it finds the atlases, builds `icon_index.json`
   by itself, then crops each icon on first request and caches the PNG.

Added more files later? Delete `icon_index.json` and restart to rescan.
Without `icon_assets/` the pages simply show no icons — nothing breaks.

## Desktop exe

```bash
pip install pyinstaller PySide6
pyinstaller --noconfirm DamageCounter.spec
```

Output: `dist/DamageCounter/DamageCounter.exe` — a self-contained folder, no
Python required on the target machine. The exe ships **without skill icons**
(see above: they are Larian's assets); to enable them, place your own
extracted `icon_assets/` folder next to `DamageCounter.exe`.

## How it works

```
DOS2 (Lua mod)  ──>  DamageCounter_Stats.json  ──>  FastAPI  ──>  pages (Vue 3)
 StatusHitEnter        in Osiris Data                app.py        polling 1s
```

- **Events, not story scripts** — the mod listens to the Script Extender's Lua
  events (`StatusHitEnter` for hits, `BeforeStatusApply` for heals) instead of
  the legacy `NRD_*` Osiris events, which only fire if some mod's story script
  references them. This is what makes it dependency-free.
- **No database, no state** — the JSON on disk is the single source of truth;
  the server re-reads it on every poll and keeps the last good payload while
  the game is mid-write.
- **Per-save by design** — stats live in `PersistentVars`, inside the savegame.
  Each run also gets a stable id and its own export file
  (`DamageCounter/<profile>/<runId>.json`), so loading another save never
  destroys a previous run's numbers.

## Console commands

| Command | Effect |
|---------|--------|
| `!export` | write the JSON now |
| `!stats` | leaderboard + labeled column dump in the console |
| `!dcprobe` | diagnostics: event hook status, hit/heal counters, per-character sanity check |
| `!hitlog` | toggle per-hit logging (flags, branch taken) |
| `!reset_stats` | zero all counters (aggregate + per-spell) |
| `!clear_non_player` | drop malformed entries (non-destructive) |

## License

[MIT](LICENSE) © ArcademMan
