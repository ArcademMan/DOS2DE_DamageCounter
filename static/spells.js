const { createApp, ref, computed, onMounted, onUnmounted } = Vue;

// Formattazione e nomi skill vivono in rows.js, condiviso tra le pagine.
const formatNumber = dcFormatNumber;

const app = createApp({
  setup() {
    const intervalMs = 1000;

    const players = ref([]);
    const reason = ref(null);
    const lastUpdate = ref(null);
    const now = ref(Date.now());
    const selectedGuid = ref(new URLSearchParams(window.location.search).get("char"));
    // Run archiviata ereditata dal leaderboard ("" = live).
    const selectedRun = new URLSearchParams(window.location.search).get("run") || "";

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
        if (body.data && Array.isArray(body.data.players)) {
          players.value = body.data.players;
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

    const sorted = computed(() => {
      const list = [...players.value];
      list.sort((a, b) => (b.stats.DamageDone || 0) - (a.stats.DamageDone || 0));
      return list;
    });

    const selectedPlayer = computed(() => {
      return (
        players.value.find((p) => p.guid === selectedGuid.value) ||
        sorted.value[0] ||
        null
      );
    });

    const skills = computed(() =>
      selectedPlayer.value && Array.isArray(selectedPlayer.value.skills)
        ? selectedPlayer.value.skills
        : []
    );

    function select(p) {
      selectedGuid.value = p.guid;
      // L'URL resta condivisibile: ricaricare la pagina riapre lo stesso pg.
      const url = new URL(window.location);
      url.searchParams.set("char", p.guid);
      history.replaceState(null, "", url);
    }

    const skillName = dcSkillName;

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
      players, sorted, selectedGuid, selectedPlayer, skills,
      select, skillName, statusText, statusClass, agoText, backHref,
      lastUpdate, intervalMs,
      fmt: formatNumber,
    };
  },
});

dcRegisterComponents(app);
app.mount("#app");
