"""
Server locale per il leaderboard di DamageCounter.

La mod scrive le statistiche in un JSON dentro la cartella Osiris Data del
gioco; questo server lo legge e lo espone alla pagina. Non c'e' database e non
c'e' stato: il file su disco e' l'unica fonte di verita'.

Avvio:
    python app.py
poi apri http://127.0.0.1:48124
(porta alta non assegnata: la 8000 e' affollata di default di altri tool)
"""

from __future__ import annotations

import json
import os
import re
from pathlib import Path

from fastapi import FastAPI
from fastapi.responses import FileResponse, JSONResponse
from fastapi.staticfiles import StaticFiles

from icon_indexer import data_dir

# --- percorso del file scritto dalla mod -----------------------------------
#
# Il lato Lua scrive solo il NOME del file: e' lo Script Extender a metterlo
# nella cartella "Osiris Data" del gioco. Qui invece bisogna ritrovarla, e non
# si puo' dare per scontato che Documenti stia sotto %USERPROFILE%\Documents:
# con OneDrive attivo, o con la cartella spostata a mano, non e' cosi'.

REL = Path("Larian Studios") / "Divinity Original Sin 2 Definitive Edition" / "Osiris Data"
STATS_FILENAME = "DamageCounter_Stats.json"


def _documents_dirs() -> list[Path]:
    """Cartelle Documenti candidate, dalla piu' attendibile alla piu' generica."""
    found: list[Path] = []

    # 1) Il percorso reale registrato da Windows, che tiene conto di OneDrive
    #    e di eventuali spostamenti.
    try:
        import winreg

        key = r"Software\Microsoft\Windows\CurrentVersion\Explorer\Shell Folders"
        with winreg.OpenKey(winreg.HKEY_CURRENT_USER, key) as k:
            personal, _ = winreg.QueryValueEx(k, "Personal")
            found.append(Path(os.path.expandvars(personal)))
    except Exception:
        pass

    # 2) Ripieghi, utili anche fuori da Windows.
    home = Path(os.environ.get("USERPROFILE") or Path.home())
    found += [home / "Documents", home / "OneDrive" / "Documents", home / "Documenti"]
    return found


def find_stats_file() -> Path:
    """Primo percorso esistente; se non ne esiste nessuno, il piu' plausibile."""
    candidates = [d / REL / STATS_FILENAME for d in _documents_dirs()]
    for c in candidates:
        if c.exists():
            return c
    # Nessun file ancora: si punta alla prima cartella Osiris Data che esiste,
    # cosi' comparira' da solo appena la mod lo scrive.
    for c in candidates:
        if c.parent.is_dir():
            return c
    return candidates[0]


STATS_PATH = Path(os.environ["DC_STATS_PATH"]) if os.environ.get("DC_STATS_PATH") else find_stats_file()

BASE_DIR = Path(__file__).parent      # moduli e pagine (nell'exe: _internal)
DATA_DIR = data_dir()                 # dati dell'utente (nell'exe: accanto all'exe)
STATIC_DIR = BASE_DIR / "static"

app = FastAPI(title="DamageCounter", docs_url=None, redoc_url=None)

# Ultimo payload valido letto. Serve perche' la lettura puo' capitare mentre il
# gioco sta riscrivendo il file: in quel caso il JSON e' troncato. Invece di
# far lampeggiare la pagina a ogni scrittura, si ripropone l'ultimo buono.
_last_good: dict | None = None
_last_mtime: float = 0.0


@app.get("/api/stats")
def get_stats() -> JSONResponse:
    global _last_good, _last_mtime

    if not STATS_PATH.exists():
        return JSONResponse(
            {
                "ok": False,
                "reason": "file-missing",
                "path": str(STATS_PATH),
                "hint": "Run !export in the Extender console, in-game.",
                "data": _last_good,
            }
        )

    try:
        mtime = STATS_PATH.stat().st_mtime
        raw = STATS_PATH.read_text(encoding="utf-8")
        data = json.loads(raw)
    except (json.JSONDecodeError, OSError):
        # Scrittura in corso o file momentaneamente illeggibile.
        return JSONResponse(
            {
                "ok": bool(_last_good),
                "reason": "partial-read",
                "path": str(STATS_PATH),
                "staleSince": _last_mtime,
                "data": _last_good,
            }
        )

    _last_good = data
    _last_mtime = mtime
    return JSONResponse({"ok": True, "path": str(STATS_PATH), "mtime": mtime, "data": data})


@app.get("/")
def index() -> FileResponse:
    return FileResponse(STATIC_DIR / "index.html")


@app.get("/spells")
def spells() -> FileResponse:
    return FileResponse(STATIC_DIR / "spells.html")


# --- icone skill -------------------------------------------------------------
#
# icon_index.json mappa ogni nome icona sulla sua texture atlas DDS +
# coordinate UV. Il PNG viene ritagliato alla prima richiesta e messo in
# cache su disco: le richieste successive servono il file gia' pronto.
#
# L'indice si puo' generare con tools/build_icon_index.py, ma non serve:
# se manca e la cartella icon_assets/ esiste (accanto all'exe, o nella root
# del progetto), viene costruito da solo all'avvio del server. Basta quindi
# mettere gli atlas estratti in icon_assets/ e riavviare l'app. Per
# rigenerarlo dopo aver aggiunto altri file: cancellare icon_index.json.

ICON_INDEX_PATH = DATA_DIR / "icon_index.json"
ICON_ASSETS_DIR = DATA_DIR / "icon_assets"
ICON_CACHE_DIR = DATA_DIR / "icon_cache"

if not ICON_INDEX_PATH.exists() and ICON_ASSETS_DIR.is_dir():
    from icon_indexer import build_index

    print(f"icon_index.json assente: scansiono {ICON_ASSETS_DIR} ...")
    _n_icons, _n_atlases = build_index(ICON_ASSETS_DIR, ICON_INDEX_PATH)
    if _n_icons:
        print(f"  indice costruito: {_n_icons} icone da {_n_atlases} atlas")
    else:
        print("  nessun atlas trovato (servono coppie .lsx + .dds): niente icone")
_icon_index: dict | None = None
_icon_index_mtime: float | None = None
_ICON_NAME_RE = re.compile(r"[A-Za-z0-9_.\-()]+")


def _load_icon_index() -> dict:
    global _icon_index, _icon_index_mtime
    try:
        mtime = ICON_INDEX_PATH.stat().st_mtime
    except OSError:
        _icon_index, _icon_index_mtime = {}, None
        return {}
    if _icon_index is None or mtime != _icon_index_mtime:
        try:
            _icon_index = json.loads(ICON_INDEX_PATH.read_text(encoding="utf-8"))
            _icon_index_mtime = mtime
        except (OSError, json.JSONDecodeError):
            _icon_index = {}
    return _icon_index


@app.get("/api/icon/{name}")
def icon(name: str):
    if not _ICON_NAME_RE.fullmatch(name):
        return JSONResponse({"ok": False, "reason": "bad-name"}, status_code=404)

    cached = ICON_CACHE_DIR / (name + ".png")
    if cached.exists():
        return FileResponse(cached, media_type="image/png")

    entry = _load_icon_index().get(name)
    if entry is None:
        return JSONResponse({"ok": False, "reason": "unknown-icon"}, status_code=404)

    try:
        from PIL import Image  # dipendenza opzionale: senza Pillow niente icone
    except ImportError:
        return JSONResponse(
            {"ok": False, "reason": "pillow-missing",
             "hint": "pip install pillow (nello stesso ambiente del server)"},
            status_code=404,
        )

    # I percorsi DDS sono assoluti (indice nuovo) o relativi al progetto
    # (indice generato dalle vecchie versioni dello script).
    dds_path = Path(entry["dds"])
    if not dds_path.is_absolute():
        dds_path = DATA_DIR / dds_path

    try:
        img = Image.open(dds_path)
        w, h = img.size
        box = (
            round(entry["u1"] * w),
            round(entry["v1"] * h),
            round(entry["u2"] * w),
            round(entry["v2"] * h),
        )
        ICON_CACHE_DIR.mkdir(parents=True, exist_ok=True)
        img.crop(box).save(cached)
    except Exception as exc:  # noqa: BLE001 - il motivo va riportato, non nascosto
        print(f"[icone] ritaglio fallito per {name}: {type(exc).__name__}: {exc}")
        return JSONResponse(
            {"ok": False, "reason": "crop-failed",
             "error": f"{type(exc).__name__}: {exc}"},
            status_code=404,
        )

    return FileResponse(cached, media_type="image/png")


app.mount("/static", StaticFiles(directory=STATIC_DIR), name="static")


if __name__ == "__main__":
    import uvicorn

    print(f"Stats file: {STATS_PATH}")
    if STATS_PATH.exists():
        print("  found")
    elif STATS_PATH.parent.is_dir():
        print("  not there yet - it will appear after the first !export")
    else:
        print("  WARNING: the Osiris Data folder does not exist.")
        print("  Pass the path manually:  DC_STATS_PATH=... python app.py")
    uvicorn.run(app, host="127.0.0.1", port=48124, log_level="warning")
