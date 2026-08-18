const { createApp, ref, computed, onMounted, onUnmounted } = Vue;

// Stessa formattazione della pagina principale.
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
    const reason = ref(null);
    const lastUpdate = ref(null);
    const now = ref(Date.now());
    const selectedGuid = ref(new URLSearchParams(window.location.search).get("char"));

    let timer = null;
    let clock = null;

    async function poll() {
      try {
        const res = await fetch("/api/stats", { cache: "no-store" });
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

    // Se il nome non e' stato tradotto dal gioco arriva l'id grezzo
    // ("Projectile_Fireball"): togli il prefisso di categoria e spezza il
    // CamelCase, che e' comunque piu' leggibile di niente.
    const SKILL_PREFIXES = /^(Projectile|Target|Shout|Zone|Cone|Storm|Rain|Summon|Wall|Dome|Tornado|Rush|Jump|MultiStrike|Quake|ProjectileStrike)_/;
    function skillName(s) {
      if (s.name && s.name !== s.id) return s.name;
      return s.id
        .replace(SKILL_PREFIXES, "")
        .replace(/_/g, " ")
        .replace(/([a-z])([A-Z])/g, "$1 $2");
    }

    const statusText = computed(() => {
      if (reason.value === "server-unreachable") return "server unreachable";
      if (reason.value === "file-missing") return "waiting for first export";
      if (reason.value === "partial-read") return "write in progress";
      return "listening";
    });

    const statusClass = computed(() => {
      if (reason.value === "server-unreachable") return "bad";
      if (reason.value === "file-missing") return "warn";
      return "good";
    });

    const agoText = computed(() => {
      if (!lastUpdate.value) return "";
      const s = Math.round((now.value - lastUpdate.value) / 1000);
      if (s < 2) return "just now";
      if (s < 60) return `${s}s ago`;
      return `${Math.floor(s / 60)}m ago`;
    });

    return {
      players, sorted, selectedGuid, selectedPlayer, skills,
      select, skillName, statusText, statusClass, agoText,
      lastUpdate, intervalMs,
      fmt: formatNumber,
    };
  },
}).mount("#app");
