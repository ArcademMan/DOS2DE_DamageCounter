# Spec PyInstaller per l'app desktop di DamageCounter.
#
# Build (dalla cartella damagecounter_web):
#     pyinstaller --noconfirm DamageCounter.spec
#
# Uscita: dist/DamageCounter/DamageCounter.exe (build "onedir": con
# QtWebEngine il onefile e' lento ad avviarsi e fragile, meglio la cartella).
#
# Nota percorsi: nel bundle i data file stanno accanto ai moduli, quindi
# Path(__file__).parent in app.py/desktop.py continua a funzionare.

from PySide6.QtCore import QLibraryInfo  # noqa: F401 - forza l'hook Qt

block_cipher = None

a = Analysis(
    ["desktop.py"],
    pathex=[],
    binaries=[],
    # NIENTE icon_assets/icon_index.json qui: sono ritagli delle texture di
    # Larian e non si possono redistribuire. L'exe li cerca a runtime nella
    # cartella icon_assets/ accanto all'eseguibile (vedi app.py).
    datas=[
        ("static", "static"),
        ("icon.png", "."),
    ],
    hiddenimports=[
        # uvicorn carica questi moduli per nome a runtime: l'analisi statica
        # non li vede e senza il server muore all'avvio.
        "uvicorn.logging",
        "uvicorn.loops.auto",
        "uvicorn.protocols.http.auto",
        "uvicorn.protocols.websockets.auto",
        "uvicorn.lifespan.on",
        "uvicorn.lifespan.off",
        "app",
    ],
    hookspath=[],
    hooksconfig={},
    runtime_hooks=[],
    excludes=[],
    win_no_prefer_redirects=False,
    win_private_assemblies=False,
    cipher=block_cipher,
    noarchive=False,
)

pyz = PYZ(a.pure, a.zipped_data, cipher=block_cipher)

exe = EXE(
    pyz,
    a.scripts,
    [],
    exclude_binaries=True,
    name="DamageCounter",
    debug=False,
    bootloader_ignore_signals=False,
    strip=False,
    upx=False,
    console=False,
    icon="icon.ico",
)

coll = COLLECT(
    exe,
    a.binaries,
    a.zipfiles,
    a.datas,
    strip=False,
    upx=False,
    name="DamageCounter",
)
