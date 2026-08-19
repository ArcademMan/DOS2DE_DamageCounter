const { createApp, ref, computed, onMounted, onUnmounted } = Vue;

// Righe della tabella di dettaglio. La chiave e' il nome del campo cosi' come
// arriva dal Lua: se ne aggiungi uno nella mod, basta aggiungerlo qui.
const ROWS = [
  { key: "DamageDone", label: "Damage dealt" },
  { key: "SummonDamageDone", label: "· from summons" },
  { key: "AllyDamageDone", label: "· on allies (friendly fire)" },
  { key: "AllyHitDone", label: "Hits on allies" },
  { key: "AllyDamageTaken", label: "Damage taken from allies" },
  { key: "SelfDamage", label: "Self-inflicted damage" },
  { key: "DamageTaken", label: "Damage taken" },
  { key: "HealingDone", label: "Healing done" },
  { key: "HealingReceived", label: "Healing received" },
  { key: "HighestDamage", label: "Biggest hit" },
  { key: "HitDone", label: "Hits landed" },
  { key: "HitTaken", label: "Hits taken" },
  { key: "CriticalHits", label: "Critical hits" },
  { key: "CriticalDmgDone", label: "Critical damage dealt" },
  { key: "CriticalHitsTaken", label: "Criticals taken" },
  { key: "CriticalDmgTaken", label: "Critical damage taken" },
  { key: "Kills", label: "Kills" },
  { key: "Death", label: "Deaths" },
  { key: "AttacksMissed", label: "Attacks missed" },
  { key: "MissedAttacks", label: "Attacks dodged" },
  { key: "AttackBlocked", label: "Attacks blocked" },
  { key: "BlockedAttack", label: "Successful blocks" },
  { key: "DamageSkillDone", label: "Skill damage dealt" },
  { key: "DamageSkillTaken", label: "Skill damage taken" },
  { key: "SurfaceDamageDone", label: "Surface damage dealt" },
  { key: "SurfaceDamageTaken", label: "Surface damage taken" },
  { key: "StatusDamageDone", label: "Status damage dealt" },
  { key: "StatusDamageTaken", label: "Status damage taken" },
  { key: "ReflectedDamage", label: "Damage reflected onto attackers" },
  { key: "DamageFromReflection", label: "Damage taken from reflection" },
  { key: "SkillUsed", label: "Skills used" },
  { key: "Resurrected", label: "Resurrections" },
  { key: "LootedCorpses", label: "Corpses looted" },
  { key: "DestroyedItem", label: "Items destroyed" },
];

// Statistiche in cui un valore ALTO e' peggio: non vanno evidenziate come
// primato. Senza questo, "morti" premierebbe chi muore di piu'.
const LOWER_IS_BETTER = new Set([
  "DamageTaken", "HitTaken", "CriticalHitsTaken", "CriticalDmgTaken",
  "Death", "AttacksMissed", "DamageSkillTaken", "SurfaceDamageTaken",
  "StatusDamageTaken", "DamageFromReflection",
  "AllyDamageDone", "AllyHitDone", "AllyDamageTaken", "SelfDamage",
]);

// Sotto i 100k si mostra il numero per intero: "1.830" e' piu' informativo di
// "1.8K", e a quelle cifre ci sta comodamente. L'abbreviazione serve solo
// quando i numeri diventano lunghi al punto da sfondare la colonna.
function formatNumber(n) {
  const v = Number(n) || 0;
  const a = Math.abs(v);
  if (a < 100_000) return Math.round(v).toLocaleString("en-US");
  if (a < 1_000_000) return Math.round(v / 1000).toLocaleString("en-US") + "K";
  return (v / 1_000_000).toFixed(1) + "M";
}

createApp({
  setup() {
    const intervalMs = 1000;

    const players = ref([]);
    const ok = ref(false);
    const reason = ref(null);
    const path = ref("");
    const lastUpdate = ref(null);
    const now = ref(Date.now());
    const showZero = ref(false);
    const sortBy = ref("DamageDone");

    // "" = live file; otherwise "profileId/runId" of an archived run.
    const selectedRun = ref(new URLSearchParams(window.location.search).get("run") || "");
    const runs = ref([]);

    let timer = null;
    let clock = null;

    async function poll() {
      try {
        const url = selectedRun.value
          ? "/api/stats?run=" + encodeURIComponent(selectedRun.value)
          : "/api/stats";
        const res = await fetch(url, { cache: "no-store" });
        const body = await res.json();
        ok.value = body.ok;
        reason.value = body.reason || null;
        path.value = body.path || "";
        if (body.data && Array.isArray(body.data.players)) {
          players.value = body.data.players;
          if (body.ok) lastUpdate.value = Date.now();
        } else if (!body.ok) {
          players.value = [];
        }
      } catch (e) {
        ok.value = false;
        reason.value = "server-unreachable";
      }
    }

    async function loadRuns() {
      try {
        const res = await fetch("/api/runs", { cache: "no-store" });
        const body = await res.json();
        if (body.ok && Array.isArray(body.runs)) runs.value = body.runs;
      } catch (e) { /* niente lista run: il selettore resta nascosto */ }
    }

    function runChanged() {
      const url = new URL(window.location);
      if (selectedRun.value) url.searchParams.set("run", selectedRun.value);
      else url.searchParams.delete("run");
      history.replaceState(null, "", url);
      players.value = [];
      lastUpdate.value = null;
      poll();
    }

    function runLabel(r) {
      const when = new Date(r.mtime * 1000).toLocaleString("en-GB", {
        day: "2-digit", month: "short", year: "numeric",
        hour: "2-digit", minute: "2-digit",
      });
      const who = (r.players || []).filter(Boolean).slice(0, 4).join(", ");
      const prof = r.profileName ? ` [${r.profileName}]` : "";
      return `${when}${prof}${who ? " - " + who : ""}`;
    }

    onMounted(() => {
      poll();
      loadRuns();
      timer = setInterval(poll, intervalMs);
      clock = setInterval(() => (now.value = Date.now()), 1000);
    });
    onUnmounted(() => {
      clearInterval(timer);
      clearInterval(clock);
    });

    const sorted = computed(() => {
      const list = [...players.value];
      list.sort((a, b) => (b.stats.DamageDone || 0) - (a.stats.DamageDone || 0));
      return list;
    });

    const totalDamage = computed(() =>
      players.value.reduce((s, p) => s + (Number(p.stats.DamageDone) || 0), 0)
    );

    const leaderGuid = computed(() => (sorted.value[0] ? sorted.value[0].guid : null));

    const rows = computed(() =>
      ROWS.map((r) => {
        const raw = {};
        const display = {};
        const values = [];
        for (const p of players.value) {
          const v = Number(p.stats[r.key]) || 0;
          raw[p.guid] = v;
          display[p.guid] = formatNumber(v);
          values.push(v);
        }
        // Il primato ha senso solo se qualcuno ha davvero un valore E se i
        // valori non sono tutti uguali: evidenziare "il migliore" quando sono
        // tutti a 90 indica un vincitore che non esiste.
        let best = null;
        const distinct = new Set(values);
        if (values.some((v) => v !== 0) && distinct.size > 1) {
          const pick = LOWER_IS_BETTER.has(r.key) ? Math.min : Math.max;
          const target = pick(...values);
          const winner = players.value.find((p) => raw[p.guid] === target);
          if (winner) best = winner.guid;
        }
        return { ...r, raw, display, values, best };
      }).filter((r) => showZero.value || r.values.some((v) => v !== 0))
    );

    function share(p) {
      if (!totalDamage.value) return 0;
      return ((Number(p.stats.DamageDone) || 0) / totalDamage.value) * 100;
    }

    // Larghezza della fetta "evocazioni" dentro la barra del giocatore.
    function summonWidth(p) {
      const dmg = Number(p.stats.DamageDone) || 0;
      if (!dmg) return 0;
      const summon = Number(p.stats.SummonDamageDone) || 0;
      return share(p) * (summon / dmg);
    }

    const statusText = computed(() => {
      if (reason.value === "server-unreachable") return "server unreachable";
      if (reason.value === "run-missing") return "run not found";
      if (selectedRun.value) return "archived run";
      if (reason.value === "file-missing") return "waiting for first export";
      if (reason.value === "partial-read") return "write in progress";
      return "listening";
    });

    const statusClass = computed(() => {
      if (reason.value === "server-unreachable") return "bad";
      if (reason.value === "run-missing") return "bad";
      if (selectedRun.value) return "warn";
      if (reason.value === "file-missing") return "warn";
      return "good";
    });

    const emptyTitle = computed(() =>
      reason.value === "file-missing" ? "No data yet" : "Empty table"
    );

    const emptyHint = computed(() => {
      if (reason.value === "server-unreachable")
        return "The Python server is not responding. Is it still running?";
      if (reason.value === "file-missing")
        return "Open the Extender console in-game and run <code>!export</code>.";
      return "The file exists but contains no characters. Land a few hits and try again.";
    });

    const agoText = computed(() => {
      if (!lastUpdate.value) return "";
      const s = Math.round((now.value - lastUpdate.value) / 1000);
      if (s < 2) return "just now";
      if (s < 60) return `${s}s ago`;
      return `${Math.floor(s / 60)}m ago`;
    });

    function rankOf(p) {
      return sorted.value.indexOf(p) + 1;
    }

    function goSpells(p) {
      let href = "/spells?char=" + encodeURIComponent(p.guid);
      if (selectedRun.value) href += "&run=" + encodeURIComponent(selectedRun.value);
      window.location.href = href;
    }

    return {
      players, sorted, rows, path, lastUpdate, intervalMs, showZero, sortBy,
      leaderGuid, statusText, statusClass, emptyTitle, emptyHint, agoText,
      share, summonWidth, rankOf,
      selectedRun, runs, runChanged, runLabel,
      goSpells,
      fmt: formatNumber,
      pct: (v) => (Number(v) || 0).toFixed(0) + "%",
    };
  },
}).mount("#app");
