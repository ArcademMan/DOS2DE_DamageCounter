const { createApp, ref, computed, onMounted, onUnmounted } = Vue;

// Elenco stats e formattazione vivono in rows.js; tabella dettagli, card
// giocatore e bottoni-gruppo sono componenti condivisi (components.js).
const formatNumber = dcFormatNumber;

const app = createApp({
  setup() {
    const intervalMs = 1000;

    const players = ref([]);
    const ok = ref(false);
    const reason = ref(null);
    const path = ref("");
    const lastUpdate = ref(null);
    const now = ref(Date.now());

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

    // Cestino sulla card: nasconde, non cancella. Il filtro sta sul server,
    // quindi al prossimo poll (entro un secondo) il personaggio sparisce da
    // tutte le pagine, e da Settings si rimette visibile.
    const toast = ref(null);
    let toastTimer = null;

    async function hideCharacter(p) {
      try {
        const res = await fetch("/api/hidden", {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({ guid: p.guid, hidden: true }),
        });
        const body = await res.json();
        if (!body.ok) {
          showToast("Could not hide " + p.name + ": " + (body.reason || "refused"));
          return;
        }
        players.value = players.value.filter((x) => x.guid !== p.guid);
        showToast(p.name + " hidden. Bring it back from");
      } catch (e) {
        showToast("Could not hide " + p.name + ": server unreachable");
      }
    }

    function showToast(text) {
      toast.value = text;
      clearTimeout(toastTimer);
      toastTimer = setTimeout(() => (toast.value = null), 6000);
    }

    // Griglia della card giocatore: etichetta + valore gia' formattato.
    const pctText = (v) => (Number(v) || 0).toFixed(0) + "%";
    function cardFields(p) {
      return [
        { label: "Taken", value: formatNumber(p.stats.DamageTaken) },
        { label: "Hits", value: formatNumber(p.stats.HitDone) },
        { label: "Avg/hit", value: formatNumber(p.derived.avgDamage) },
        { label: "Max hit", value: formatNumber(p.stats.HighestDamage) },
        { label: "Crits", value: pctText(p.derived.critRate) },
        { label: "Missed", value: pctText(p.derived.missRate) },
        { label: "Kills", value: formatNumber(p.stats.Kills) },
        { label: "Deaths", value: formatNumber(p.stats.Death) },
        { label: "Summons", value: pctText(p.derived.summonShare) },
      ];
    }

    function goSpells(p) {
      let href = "/spells?char=" + encodeURIComponent(p.guid);
      if (selectedRun.value) href += "&run=" + encodeURIComponent(selectedRun.value);
      window.location.href = href;
    }

    const fightsHref = computed(() =>
      selectedRun.value ? "/fights?run=" + encodeURIComponent(selectedRun.value) : "/fights"
    );

    return {
      players, sorted, path, lastUpdate, intervalMs,
      leaderGuid, statusText, statusClass, emptyTitle, emptyHint, agoText,
      share, summonWidth, rankOf, cardFields,
      hideCharacter, toast,
      selectedRun, runs, runChanged, runLabel, fightsHref,
      goSpells,
      fmt: formatNumber,
    };
  },
});

dcRegisterComponents(app);
app.mount("#app");
