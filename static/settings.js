const { createApp, ref, computed, onMounted } = Vue;

createApp({
  setup() {
    const characters = ref([]);
    const statsPath = ref("");
    const error = ref(null);

    async function load() {
      try {
        const res = await fetch("/api/settings", { cache: "no-store" });
        const body = await res.json();
        if (body.ok) {
          characters.value = body.characters || [];
          statsPath.value = body.statsPath || "";
          error.value = null;
        } else {
          error.value = body.reason || "unknown";
        }
      } catch (e) {
        error.value = "server-unreachable";
      }
    }

    async function toggle(c) {
      const wanted = !c.hidden;
      try {
        const res = await fetch("/api/hidden", {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({ guid: c.guid, hidden: wanted }),
        });
        const body = await res.json();
        if (!body.ok) {
          // Niente cambio muto: se il server rifiuta, la riga resta com'era
          // e lo stato in alto lo dice.
          error.value = body.reason || "refused";
          return;
        }
        c.hidden = wanted;
        error.value = null;
      } catch (e) {
        error.value = "server-unreachable";
      }
    }

    onMounted(load);

    const statusText = computed(() => {
      if (error.value === "server-unreachable") return "server unreachable";
      if (error.value) return "error: " + error.value;
      return "saved automatically";
    });

    const statusClass = computed(() => (error.value ? "bad" : "good"));

    return { characters, statsPath, toggle, statusText, statusClass };
  },
}).mount("#app");
