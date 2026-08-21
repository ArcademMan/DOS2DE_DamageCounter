// Componenti Vue condivisi tra le pagine. Caricare dopo rows.js e chiamare
// dcRegisterComponents(app) prima di app.mount().
//
// - dc-player-card : card giocatore (testata, valore hero, barra quota, griglia)
// - dc-stat-table  : tabella statistiche completa con bottoni-gruppo e toggle zero
// - dc-spells-table: tabella spell con icone
//
// Un solo posto per ogni pezzo di grafica: leaderboard, /spells e /fights
// montano questi, non copie proprie.

const DC_GROUPS = [
  { id: "all", icon: "☰", label: "All" },
  { id: "offense", icon: "⚔️", label: "Offense" },
  { id: "defense", icon: "🛡️", label: "Defense" },
  { id: "support", icon: "✨", label: "Support" },
  { id: "friendly", icon: "⚠️", label: "Friendly fire" },
  { id: "misc", icon: "📦", label: "Misc" },
];

function dcRegisterComponents(app) {
  app.component("dc-player-card", {
    props: {
      name: { type: String, required: true },
      damage: { type: Number, default: 0 },
      sharePct: { type: Number, default: 0 },
      summonPct: { type: Number, default: 0 },
      summonTitle: { type: String, default: "" },
      // [{label, value}] gia' formattati: la card non decide cosa mostrare.
      fields: { type: Array, default: () => [] },
      rank: { type: Number, default: 0 },
      leader: { type: Boolean, default: false },
      clickable: { type: Boolean, default: false },
    },
    emits: ["select"],
    computed: {
      heroText() { return dcFormatNumber(this.damage); },
    },
    template: `
      <article
        class="card"
        :class="{ leader: leader, clickable: clickable }"
        :title="clickable ? 'Open spell breakdown' : null"
        @click="clickable && $emit('select')">
        <div class="card-head">
          <span v-if="rank" class="rank">{{ rank }}</span>
          <h2>{{ name }}</h2>
        </div>
        <div class="hero">
          <div class="hero-value">{{ heroText }}</div>
          <div class="hero-label">damage dealt</div>
        </div>
        <div class="bar" :title="sharePct.toFixed(1) + '% of total'">
          <div class="bar-fill" :style="{ width: sharePct + '%' }"></div>
          <div
            v-if="summonPct > 0"
            class="bar-summon"
            :style="{ width: summonPct + '%' }"
            :title="summonTitle"></div>
        </div>
        <dl class="grid">
          <div v-for="f in fields" :key="f.label">
            <dt>{{ f.label }}</dt><dd>{{ f.value }}</dd>
          </div>
        </dl>
      </article>`,
  });

  app.component("dc-stat-table", {
    props: {
      // [{guid, name, stats}] : payload generale o delta di una fight.
      players: { type: Array, required: true },
      // I bottoni-gruppo hanno senso sulla tabella lunga del leaderboard;
      // su un recap corto si possono spegnere.
      groupButtons: { type: Boolean, default: true },
      title: { type: String, default: "Details" },
      subtitle: { type: String, default: "" },
    },
    data() {
      return { activeGroup: "all", showZero: false, groups: DC_GROUPS };
    },
    computed: {
      rows() {
        let all = [...DC_ROWS];
        const anchor = all.findIndex((r) => r.key === "VitalityDamageTaken");
        all.splice(anchor + 1, 0, ...dcTypeRows(this.players.map((p) => p.stats || {})));

        if (this.activeGroup !== "all") {
          all = all.filter((r) => r.group === this.activeGroup);
        }

        return all.map((r) => {
          const raw = {};
          const display = {};
          const values = [];
          for (const p of this.players) {
            const s = p.stats || {};
            const v = Number(r.get ? r.get(s) : s[r.key]) || 0;
            raw[p.guid] = v;
            display[p.guid] = dcFormatNumber(v);
            values.push(v);
          }
          // Il primato ha senso solo se qualcuno ha davvero un valore E se i
          // valori non sono tutti uguali.
          let best = null;
          const distinct = new Set(values);
          if (values.some((v) => v !== 0) && distinct.size > 1) {
            const lower = r.lower || DC_LOWER_IS_BETTER.has(r.key);
            const pick = lower ? Math.min : Math.max;
            const target = pick(...values);
            const winner = this.players.find((p) => raw[p.guid] === target);
            if (winner) best = winner.guid;
          }
          return { ...r, raw, display, values, best };
        }).filter((r) => this.showZero || r.values.some((v) => v !== 0));
      },
    },
    template: `
      <div>
        <nav class="groupbar" v-if="groupButtons">
          <button
            v-for="g in groups"
            :key="g.id"
            class="groupbtn"
            :class="{ active: activeGroup === g.id }"
            @click="activeGroup = g.id">
            <span class="gicon">{{ g.icon }}</span>{{ g.label }}
          </button>
        </nav>
        <section class="table-wrap">
          <div class="table-head">
            <h3>{{ title }}</h3>
            <span v-if="subtitle" class="muted">{{ subtitle }}</span>
            <label class="toggle">
              <input type="checkbox" v-model="showZero">
              <span>show zero rows</span>
            </label>
          </div>
          <table>
            <thead>
              <tr>
                <th class="metric">Stat</th>
                <th v-for="p in players" :key="p.guid">{{ p.name }}</th>
              </tr>
            </thead>
            <tbody>
              <tr v-for="row in rows" :key="row.key">
                <td class="metric">{{ row.label }}</td>
                <td
                  v-for="p in players"
                  :key="p.guid"
                  :class="{ best: row.values.length > 1 && row.best === p.guid, zero: !row.raw[p.guid] }">
                  {{ row.display[p.guid] }}
                </td>
              </tr>
            </tbody>
          </table>
        </section>
      </div>`,
  });

  app.component("dc-spells-table", {
    props: {
      skills: { type: Array, required: true },
    },
    methods: {
      fmt: dcFormatNumber,
      skillName: dcSkillName,
    },
    template: `
      <table>
        <thead>
          <tr>
            <th class="metric">Spell</th>
            <th>Uses</th>
            <th>Hits</th>
            <th>Damage</th>
            <th>Avg/hit</th>
            <th>Crits</th>
            <th>Crit damage</th>
            <th>Max hit</th>
          </tr>
        </thead>
        <tbody>
          <tr v-for="s in skills" :key="s.id">
            <td class="metric" :title="s.id">
              <img
                v-if="s.icon"
                class="skillicon"
                :src="'/api/icon/' + encodeURIComponent(s.icon)"
                alt=""
                loading="lazy"
                @error="$event.target.style.display = 'none'">
              <span>{{ skillName(s) }}</span>
            </td>
            <td>{{ fmt(s.uses) }}</td>
            <td>{{ fmt(s.hits) }}</td>
            <td :class="{ zero: !s.damage }">{{ fmt(s.damage) }}</td>
            <td>{{ s.hits ? fmt(s.damage / s.hits) : "–" }}</td>
            <td :class="{ zero: !s.critHits }">{{ fmt(s.critHits) }}</td>
            <td :class="{ zero: !s.critDamage }">{{ fmt(s.critDamage) }}</td>
            <td>{{ s.maxHit ? fmt(s.maxHit) : "–" }}</td>
          </tr>
        </tbody>
      </table>`,
  });
}
