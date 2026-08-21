const { createApp, ref, computed, onMounted, onUnmounted } = Vue;

// Elenco stats condiviso con il leaderboard (rows.js): il dettaglio di una
// fight mostra TUTTO quello che si e' mosso durante lo scontro, non un
// riassunto scelto da noi.

const app = createApp({
  setup() {
    const intervalMs = 1000;

    const rawFights = ref([]);
    const reason = ref(null);
    const lastUpdate = ref(null);
    const now = ref(Date.now());
    const params = new URLSearchParams(window.location.search);
    const selectedRun = params.get("run") || "";
    // ?fight=N apre la pagina dedicata a quello scontro; senza, la lista.
    const selectedFightN = parseInt(params.get("fight"), 10) || null;

    let timer = null;
    let clock = null;

    async function poll() {
      try {
        const url = selectedRun
          ? "/api/stats?run=" + encodeURIComponent(selectedRun)
          : "/api/stats";
        const res = await fetch(url, { cache: "no-store" });
        const body = await res.json();
        reason.value = body.reason || null;
        if (body.data) {
          // Una lista vuota arriva dal Lua come {} invece che []: si accetta
          // solo la forma array, il resto vale come "nessuna fight".
          const f = body.data.fights;
          rawFights.value = Array.isArray(f) ? f : [];
          if (body.ok) lastUpdate.value = Date.now();
        }
      } catch (e) {
        reason.value = "server-unreachable";
      }
    }

    onMounted(() => {
      poll();
      timer = setInterval(poll, intervalMs);
      clock = setInterval(() => (now.value = Date.now()), 1000);
    });
    onUnmounted(() => {
      clearInterval(timer);
      clearInterval(clock);
    });

    // Ordine cronologico: #1 in alto, l'ultima fight in fondo. Il numero
    // arriva dalla mod (seq) ed e' stabile: non cambia quando le fight
    // vecchie escono dalla lista.
    const fights = computed(() =>
      rawFights.value.map((f, i) => ({
        ...f,
        n: f.seq || i + 1,
        players: (Array.isArray(f.players) ? f.players : []).map((p) => ({
          ...p,
          skills: Array.isArray(p.skills) ? p.skills : [],
        })),
        enemies: Array.isArray(f.enemies) ? f.enemies : [],
        regionName: dcLevelName(f.region),
        duration: formatDuration(f),
        whenText: formatWhen(f),
      }))
    );

    // Data reale dello scontro; le fight registrate prima che la mod
    // salvasse l'orologio non ce l'hanno, e la lista mostra la durata.
    function formatWhen(f) {
      if (!f.when) return "";
      return new Date(f.when * 1000).toLocaleString("en-GB", {
        day: "2-digit", month: "short",
        hour: "2-digit", minute: "2-digit",
      });
    }

    // Derivate della singola fight: non vengono salvate perche' ricavabili
    // dai delta, si calcolano qui (stesse formule del leaderboard).
    function derived(p) {
      const s = p.stats || {};
      const hits = Number(s.HitDone) || 0;
      return {
        avgDamage: hits > 0 ? (Number(s.DamageDone) || 0) / hits : 0,
        critRate: hits > 0 ? ((Number(s.CriticalHits) || 0) / hits) * 100 : 0,
      };
    }

    function fightTotal(f) {
      return f.players.reduce((t, p) => t + (Number(p.stats.DamageDone) || 0), 0);
    }

    function share(f, p) {
      const total = fightTotal(f);
      if (!total) return 0;
      return ((Number(p.stats.DamageDone) || 0) / total) * 100;
    }

    function fightLeader(f) {
      let best = null;
      let bestDmg = -1;
      for (const p of f.players) {
        const d = Number(p.stats.DamageDone) || 0;
        if (d > bestDmg) {
          best = p.guid;
          bestDmg = d;
        }
      }
      return bestDmg > 0 ? best : null;
    }

    function playersWithSkills(f) {
      return f.players.filter((p) => p.skills.length > 0);
    }

    const selectedFight = computed(() =>
      selectedFightN ? fights.value.find((f) => f.n === selectedFightN) || null : null
    );

    // Giocatore selezionato nella sezione Spells della fight (chips):
    // default il primo che ha castato qualcosa.
    const spellsGuid = ref(null);
    const spellsPlayer = computed(() => {
      const f = selectedFight.value;
      if (!f) return null;
      const list = playersWithSkills(f);
      if (!list.length) return null;
      return list.find((p) => p.guid === spellsGuid.value) || list[0];
    });

    function fightHref(f) {
      let href = "/fights?fight=" + f.n;
      if (selectedRun) href += "&run=" + encodeURIComponent(selectedRun);
      return href;
    }

    const listHref = computed(() =>
      selectedRun ? "/fights?run=" + encodeURIComponent(selectedRun) : "/fights"
    );

    function formatDuration(f) {
      const ms = Number(f.endedAt) - Number(f.startedAt);
      if (!isFinite(ms) || ms <= 0) return "";
      const s = Math.round(ms / 1000);
      if (s < 60) return s + "s";
      return Math.floor(s / 60) + "m " + (s % 60) + "s";
    }

    // Una fight in corso resta selezionata anche mentre i dati cambiano:
    // la pagina si aggiorna da sola col polling gia' attivo.
    const liveFight = computed(() => fights.value.find((f) => f.active) || null);

    function enemiesText(f) {
      if (!f.enemies.length) return "";
      return f.enemies
        .map((e) => (e.n > 1 ? `${e.name} ×${e.n}` : e.name))
        .join(", ");
    }

    // Griglia della card giocatore per una fight: valori gia' formattati.
    const pctText = (v) => (Number(v) || 0).toFixed(0) + "%";
    function cardFields(p) {
      const s = p.stats || {};
      return [
        { label: "Taken", value: dcFormatNumber(s.DamageTaken || 0) },
        { label: "Hits", value: dcFormatNumber(s.HitDone || 0) },
        { label: "Avg/hit", value: dcFormatNumber(derived(p).avgDamage) },
        { label: "Max hit", value: s.HighestDamage ? dcFormatNumber(s.HighestDamage) : "–" },
        { label: "Crits", value: pctText(derived(p).critRate) },
        { label: "Healing", value: dcFormatNumber(s.HealingDone || 0) },
        { label: "CC", value: dcFormatNumber(s.CCInflicted || 0) },
        { label: "Kills", value: dcFormatNumber(s.Kills || 0) },
        { label: "Deaths", value: dcFormatNumber(s.Death || 0) },
      ];
    }

    const statusText = computed(() => {
      if (reason.value === "server-unreachable") return "server unreachable";
      if (reason.value === "run-missing") return "run not found";
      if (selectedRun) return "archived run";
      if (reason.value === "file-missing") return "waiting for first export";
      if (reason.value === "partial-read") return "write in progress";
      return "listening";
    });

    const statusClass = computed(() => {
      if (reason.value === "server-unreachable") return "bad";
      if (reason.value === "run-missing") return "bad";
      if (selectedRun) return "warn";
      if (reason.value === "file-missing") return "warn";
      return "good";
    });

    const backHref = computed(() =>
      selectedRun ? "/?run=" + encodeURIComponent(selectedRun) : "/"
    );

    const agoText = computed(() => {
      if (!lastUpdate.value) return "";
      const s = Math.round((now.value - lastUpdate.value) / 1000);
      if (s < 2) return "just now";
      if (s < 60) return `${s}s ago`;
      return `${Math.floor(s / 60)}m ago`;
    });

    return {
      fights, selectedFight, fightHref, listHref, enemiesText, liveFight,
      derived, share, fightLeader, playersWithSkills, cardFields,
      spellsGuid, spellsPlayer,
      statusText, statusClass, backHref, agoText,
      lastUpdate, intervalMs,
      fmt: dcFormatNumber,
    };
  },
});

dcRegisterComponents(app);
app.mount("#app");
