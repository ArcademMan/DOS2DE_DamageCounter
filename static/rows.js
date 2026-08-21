// Definizioni condivise tra le pagine (caricare PRIMA dello script di pagina).
// Un solo posto per l'elenco delle statistiche: leaderboard e fights mostrano
// lo stesso set, aggiungere una stat qui la porta ovunque.

const DC_ROWS = [
  { key: "DamageDone", label: "Damage dealt", group: "offense" },
  { key: "SummonDamageDone", label: "· from summons", group: "offense" },
  { key: "DamageToArmour", label: "· to armour", group: "offense" },
  { key: "VitalityDamageDone", label: "· to vitality", group: "offense" },
  { key: "AllyDamageDone", label: "· on allies (friendly fire)", group: "friendly" },
  { key: "AllyHitDone", label: "Hits on allies", group: "friendly" },
  { key: "AllyDamageTaken", label: "Damage taken from allies", group: "friendly" },
  { key: "SelfDamage", label: "Self-inflicted damage", group: "friendly" },
  { key: "DamageTaken", label: "Damage taken", group: "defense" },
  { key: "ArmourAbsorbed", label: "· absorbed by armour", group: "defense" },
  { key: "VitalityDamageTaken", label: "· to vitality", group: "defense" },
  { key: "HealingDone", label: "Healing done", group: "support" },
  { key: "HealingReceived", label: "Healing received", group: "support" },
  { key: "OverhealDone", label: "· overhealing (wasted)", group: "support" },
  { key: "OverhealReceived", label: "Overhealing received", group: "support" },
  { key: "ArmourRestoredDone", label: "Armour restored", group: "support" },
  { key: "ArmourRestoredReceived", label: "Armour restored on self", group: "support" },
  { key: "HighestDamage", label: "Biggest hit", group: "offense" },
  { key: "HitDone", label: "Hits landed", group: "offense" },
  { key: "HitTaken", label: "Hits taken", group: "defense" },
  { key: "CriticalHits", label: "Critical hits", group: "offense" },
  { key: "CriticalDmgDone", label: "Critical damage dealt", group: "offense" },
  { key: "CriticalHitsTaken", label: "Criticals taken", group: "defense" },
  { key: "CriticalDmgTaken", label: "Critical damage taken", group: "defense" },
  { key: "Kills", label: "Kills", group: "misc" },
  { key: "Death", label: "Deaths", group: "misc" },
  { key: "CCInflicted", label: "Crowd control inflicted", group: "support" },
  { key: "CCReceived", label: "Crowd control received", group: "support" },
  { key: "AttacksMissed", label: "Attacks missed", group: "offense" },
  { key: "MissedAttacks", label: "Attacks dodged", group: "defense" },
  { key: "AttackBlocked", label: "Attacks blocked", group: "offense" },
  { key: "BlockedAttack", label: "Successful blocks", group: "defense" },
  { key: "DamageSkillDone", label: "Skill damage dealt", group: "offense" },
  { key: "DamageSkillTaken", label: "Skill damage taken", group: "defense" },
  { key: "SurfaceDamageDone", label: "Surface damage dealt", group: "offense" },
  { key: "SurfaceDamageTaken", label: "Surface damage taken", group: "defense" },
  { key: "StatusDamageDone", label: "Status damage dealt", group: "offense" },
  { key: "StatusDamageTaken", label: "Status damage taken", group: "defense" },
  { key: "ReflectedDamage", label: "Damage reflected onto attackers", group: "offense" },
  { key: "DamageFromReflection", label: "Damage taken from reflection", group: "defense" },
  { key: "SkillUsed", label: "Skills used", group: "misc" },
  { key: "Resurrected", label: "Resurrections", group: "support" },
  { key: "LootedCorpses", label: "Corpses looted", group: "misc" },
  { key: "DestroyedItem", label: "Items destroyed", group: "misc" },
];

// Statistiche in cui un valore ALTO e' peggio: non vanno evidenziate come
// primato. Senza questo, "morti" premierebbe chi muore di piu'.
const DC_LOWER_IS_BETTER = new Set([
  "DamageTaken", "HitTaken", "CriticalHitsTaken", "CriticalDmgTaken",
  "Death", "AttacksMissed", "DamageSkillTaken", "SurfaceDamageTaken",
  "StatusDamageTaken", "DamageFromReflection",
  "AllyDamageDone", "AllyHitDone", "AllyDamageTaken", "SelfDamage",
  "ArmourAbsorbed", "VitalityDamageTaken",
  "CCReceived",
  // Cura sprecata su chi era gia' pieno: meno ce n'e', meglio si e' curato.
  "OverhealDone",
]);

// Righe dinamiche per tipo di danno, costruite dai dati davvero presenti
// (statsList = array di oggetti stats, con DamageByType/DamageTakenByType).
function dcTypeRows(statsList) {
  const types = new Set();
  for (const s of statsList) {
    for (const t in s.DamageByType || {}) types.add(t);
    for (const t in s.DamageTakenByType || {}) types.add(t);
  }
  return [...types].sort().flatMap((t) => [
    { key: "typedone-" + t, label: t + " damage dealt", group: "offense",
      get: (stats) => (stats.DamageByType || {})[t] || 0 },
    { key: "typetaken-" + t, label: t + " damage taken", lower: true, group: "defense",
      get: (stats) => (stats.DamageTakenByType || {})[t] || 0 },
  ]);
}

// Numeri per intero o abbreviati. La scelta e' un ref Vue, cosi' cambiarla
// ridisegna tutto quello che formatta numeri senza ricaricare la pagina, e
// vive in localStorage per restare tale al riavvio (app desktop compresa).
// Nota: l'abbreviazione e' SOLO visualizzazione, nel JSON i valori sono
// sempre interi completi.
const DC_FULL_NUMBERS_KEY = "dc-full-numbers";
const dcFullNumbers = Vue.ref(localStorage.getItem(DC_FULL_NUMBERS_KEY) === "1");

function dcSetFullNumbers(on) {
  dcFullNumbers.value = !!on;
  localStorage.setItem(DC_FULL_NUMBERS_KEY, on ? "1" : "0");
}

// Sotto i 100k si mostra il numero per intero: "1.830" e' piu' informativo di
// "1.8K", e a quelle cifre ci sta comodamente. L'abbreviazione serve solo
// quando i numeri diventano lunghi al punto da sfondare la colonna.
function dcFormatNumber(n) {
  const v = Number(n) || 0;
  const a = Math.abs(v);
  if (dcFullNumbers.value) return Math.round(v).toLocaleString("en-US");
  if (a < 100_000) return Math.round(v).toLocaleString("en-US");
  if (a < 1_000_000) return Math.round(v / 1000).toLocaleString("en-US") + "K";
  return (v / 1_000_000).toFixed(1) + "M";
}

// Id livello -> nome leggibile. I giocatori non hanno idea di cosa sia
// "RC_Main": qui i livelli della campagna DOS2 DE; per gli id sconosciuti
// (mod, GM) un fallback che almeno toglie prefissi e underscore.
const DC_LEVEL_NAMES = {
  TUT_Tutorial_A: "The Merryweather",
  FJ_FortJoy_Main: "Fort Joy",
  LV_HoE_Main: "Lady Vengeance",
  RC_Main: "Reaper's Coast",
  CoS_Main: "The Nameless Isle",
  Arx_Main: "Arx",
  ARX_Main: "Arx",
  ARX_Endgame: "Arx",
};

// Se il nome della skill non e' stato tradotto dal gioco arriva l'id grezzo
// ("Projectile_Fireball"): via il prefisso di categoria e spezzato il
// CamelCase, che e' comunque piu' leggibile di niente.
const DC_SKILL_PREFIXES = /^(Projectile|Target|Shout|Zone|Cone|Storm|Rain|Summon|Wall|Dome|Tornado|Rush|Jump|MultiStrike|Quake|ProjectileStrike)_/;
function dcSkillName(s) {
  if (s.name && s.name !== s.id) return s.name;
  return s.id
    .replace(DC_SKILL_PREFIXES, "")
    .replace(/_/g, " ")
    .replace(/([a-z])([A-Z])/g, "$1 $2");
}

function dcLevelName(id) {
  if (!id) return "";
  if (DC_LEVEL_NAMES[id]) return DC_LEVEL_NAMES[id];
  return id
    .replace(/^[A-Za-z]{2,4}_/, "")
    .replace(/_Main$/, "")
    .replace(/_/g, " ");
}
