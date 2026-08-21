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
import time
from pathlib import Path

from fastapi import Body, FastAPI
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


# --- personaggi nascosti ------------------------------------------------------
#
# Alcuni NPC entrano nel gruppo per una parte della storia e finiscono nelle
# statistiche insieme ai protagonisti. Qui si possono nascondere: NON si
# cancella niente, la mod continua a tracciarli e basta rimetterli visibili
# dalla pagina Settings. Il filtro sta lato server, cosi' vale per tutte le
# pagine e per l'app desktop allo stesso modo.
#
# Il registro dei nomi serve proprio perche' i nascosti spariscono dal
# payload: senza, la pagina Settings non saprebbe come chiamarli.

SETTINGS_PATH = DATA_DIR / "settings.json"
_settings: dict | None = None


def _load_settings() -> dict:
    global _settings
    if _settings is None:
        try:
            data = json.loads(SETTINGS_PATH.read_text(encoding="utf-8"))
        except (OSError, json.JSONDecodeError):
            data = {}
        data.setdefault("hidden", [])
        data.setdefault("known", {})   # guid -> ultimo nome visto
        _settings = data
    return _settings


def _save_settings() -> None:
    try:
        SETTINGS_PATH.write_text(json.dumps(_load_settings(), indent=2),
                                 encoding="utf-8")
    except OSError as exc:
        print(f"[settings] impossibile salvare {SETTINGS_PATH.name}: {exc}")


def _apply_hidden(data: dict) -> None:
    """Toglie dal payload i personaggi nascosti, aggiornando il registro nomi.

    Filtra anche dentro le fight: un personaggio nascosto non deve ricomparire
    nei riepiloghi degli scontri. Le percentuali (quota danni) si ricalcolano
    da sole sulla pagina, sui soli personaggi rimasti, che e' il senso stesso
    di nasconderli.
    """
    settings = _load_settings()
    hidden = set(settings.get("hidden", []))
    known = settings.get("known", {})
    changed = False

    for p in data.get("players", []) or []:
        guid, name = p.get("guid"), p.get("name")
        if guid and name and known.get(guid) != name:
            known[guid] = name
            changed = True
    if changed:
        _save_settings()

    if not hidden:
        return

    data["players"] = [p for p in data.get("players", []) or []
                       if p.get("guid") not in hidden]
    data["playerCount"] = len(data["players"])

    fights = data.get("fights")
    if isinstance(fights, list):
        for f in fights:
            if isinstance(f, dict) and isinstance(f.get("players"), list):
                f["players"] = [p for p in f["players"]
                                if p.get("guid") not in hidden]


# --- data reale delle fight --------------------------------------------------
#
# Il Lua della mod non ha un orologio (il sandbox dell'Extender non espone
# os.time; il suo tempo e' monotonico, buono solo per le durate). La data di
# ogni scontro la assegna quindi QUESTO server: la prima volta che una fight
# compare nel file live riceve l'ora corrente, memorizzata su disco cosi' da
# sopravvivere ai riavvii e valere anche rivedendo la run archiviata.

FIGHT_TIMES_PATH = DATA_DIR / "fight_times.json"
_fight_times: dict[str, int] | None = None


def _load_fight_times() -> dict[str, int]:
    global _fight_times
    if _fight_times is None:
        try:
            _fight_times = json.loads(FIGHT_TIMES_PATH.read_text(encoding="utf-8"))
        except (OSError, json.JSONDecodeError):
            _fight_times = {}
    return _fight_times


def _fight_keys(run_id, f: dict) -> tuple[str, str | None]:
    """Chiave del timestamp, piu' l'eventuale chiave vecchia da migrare.

    La chiave nuova usa il numero progressivo dello scontro, stabile per
    definizione. Quella vecchia includeva endedAt, che per una fight IN CORSO
    cambia a ogni export: con quella, ogni aggiornamento avrebbe creato una
    voce nuova invece di ritrovare la sua.
    """
    legacy = f"{run_id}|{f.get('combatId')}|{f.get('startedAt')}|{f.get('endedAt')}"
    seq = f.get("seq")
    if seq is None:
        return legacy, None
    return f"{run_id}|seq{seq}", legacy


def _stamp_fights(data: dict, stamp_new: bool) -> None:
    """Aggiunge 'when' (epoch) alle fight del payload.

    stamp_new=True (file live): le fight mai viste ricevono l'ora corrente e
    vengono ricordate. False (run archiviate): solo lookup, una fight mai
    passata dal live su questa macchina resta senza data.
    """
    fights = data.get("fights")
    if not isinstance(fights, list) or not fights:
        return
    times = _load_fight_times()
    run_id = data.get("runId")
    changed = False
    for f in fights:
        if not isinstance(f, dict):
            continue
        # Una fight in corso e' per definizione "adesso": niente da ricordare,
        # la data definitiva la prende quando il combattimento finisce.
        if f.get("active"):
            f["when"] = int(time.time())
            continue
        key, legacy = _fight_keys(run_id, f)
        when = times.get(key)
        if when is None and legacy is not None and legacy in times:
            when = times.pop(legacy)   # migrazione dalla chiave vecchia
            times[key] = when
            changed = True
        if when is None and stamp_new:
            when = int(time.time())
            times[key] = when
            changed = True
        if when is not None:
            f["when"] = when
    if changed:
        try:
            FIGHT_TIMES_PATH.write_text(json.dumps(times), encoding="utf-8")
        except OSError as exc:
            print(f"[fights] impossibile salvare {FIGHT_TIMES_PATH.name}: {exc}")


# Le run archiviate: la mod scrive una copia per partita in
#   Osiris Data\DamageCounter\<profileId>\<runId>.json
# accanto al file live. Da qui si possono rileggere partite vecchie.
RUNS_DIR = STATS_PATH.parent / "DamageCounter"
_RUN_PART_RE = re.compile(r"[A-Za-z0-9_.\-]+")


@app.get("/api/runs")
def list_runs() -> JSONResponse:
    runs: list[dict] = []
    if RUNS_DIR.is_dir():
        for prof_dir in RUNS_DIR.iterdir():
            if not prof_dir.is_dir():
                continue
            for f in prof_dir.glob("*.json"):
                entry = {
                    "profileId": prof_dir.name,
                    "runId": f.stem,
                    "run": f"{prof_dir.name}/{f.stem}",
                    "mtime": f.stat().st_mtime,
                }
                # I metadati leggibili (nome profilo, personaggi) stanno solo
                # dentro il file: lettura intera, ma i file sono piccoli e
                # la lista si chiede una volta, non in polling.
                try:
                    data = json.loads(f.read_text(encoding="utf-8"))
                    entry["profileName"] = data.get("profileName")
                    entry["playerCount"] = data.get("playerCount")
                    entry["players"] = [
                        p.get("name") for p in data.get("players", [])
                    ]
                except (OSError, json.JSONDecodeError):
                    entry["unreadable"] = True
                runs.append(entry)
    runs.sort(key=lambda r: r["mtime"], reverse=True)
    return JSONResponse({"ok": True, "dir": str(RUNS_DIR), "runs": runs})


@app.get("/api/stats")
def get_stats(run: str | None = None) -> JSONResponse:
    global _last_good, _last_mtime

    # Una run archiviata: file statico, niente cache ultimo-buono.
    if run:
        parts = run.split("/")
        if len(parts) != 2 or not all(_RUN_PART_RE.fullmatch(p) for p in parts):
            return JSONResponse({"ok": False, "reason": "bad-run"}, status_code=400)
        f = RUNS_DIR / parts[0] / (parts[1] + ".json")
        if not f.exists():
            return JSONResponse({"ok": False, "reason": "run-missing",
                                 "path": str(f)}, status_code=404)
        try:
            data = json.loads(f.read_text(encoding="utf-8"))
        except (OSError, json.JSONDecodeError):
            return JSONResponse({"ok": False, "reason": "run-unreadable",
                                 "path": str(f)}, status_code=500)
        _stamp_fights(data, stamp_new=False)
        _apply_hidden(data)
        return JSONResponse({"ok": True, "path": str(f), "archived": True,
                             "mtime": f.stat().st_mtime, "data": data})

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

    _stamp_fights(data, stamp_new=True)
    _last_good = data
    _last_mtime = mtime
    _apply_hidden(data)
    return JSONResponse({"ok": True, "path": str(STATS_PATH), "mtime": mtime, "data": data})


@app.get("/")
def index() -> FileResponse:
    return FileResponse(STATIC_DIR / "index.html")


@app.get("/spells")
def spells() -> FileResponse:
    return FileResponse(STATIC_DIR / "spells.html")


@app.get("/fights")
def fights() -> FileResponse:
    return FileResponse(STATIC_DIR / "fights.html")


@app.get("/settings")
def settings_page() -> FileResponse:
    return FileResponse(STATIC_DIR / "settings.html")


_GUID_RE = re.compile(
    r"[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}")


@app.get("/api/settings")
def get_settings() -> JSONResponse:
    s = _load_settings()
    hidden = set(s.get("hidden", []))
    known = s.get("known", {})
    chars = [{"guid": g, "name": n, "hidden": g in hidden}
             for g, n in known.items()]
    # Un nascosto di cui si e' perso il nome resta comunque in elenco, altrimenti
    # non ci sarebbe piu' modo di rimetterlo visibile.
    for g in hidden:
        if g not in known:
            chars.append({"guid": g, "name": g, "hidden": True})
    chars.sort(key=lambda c: c["name"].lower())
    return JSONResponse({"ok": True, "characters": chars,
                         "statsPath": str(STATS_PATH)})


@app.post("/api/hidden")
def set_hidden(payload: dict = Body(...)) -> JSONResponse:
    guid = payload.get("guid")
    if not isinstance(guid, str) or not _GUID_RE.fullmatch(guid):
        return JSONResponse({"ok": False, "reason": "bad-guid"}, status_code=400)
    s = _load_settings()
    hidden = [g for g in s.get("hidden", []) if g != guid]
    if payload.get("hidden"):
        hidden.append(guid)
    s["hidden"] = hidden
    _save_settings()
    return JSONResponse({"ok": True, "hidden": hidden})


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
