PersistentVars = PersistentVars or { DamageStats = {}, LootedCorpses = {} }

-- LeaderLib rimosso. Le due variabili che stavano qui (LeaderLib, GameHelpers)
-- non venivano mai usate, e l'unico aggancio reale - Mods.LeaderLib.Import()
-- in Shared.lua - ripristinava i PersistentVars da un file su disco globale
-- all'installazione, facendo rientrare le statistiche di partite precedenti
-- in quelle nuove. Lo Script Extender li salva gia' dentro al savegame.
local DC_NULL = "NULL_00000000-0000-0000-0000-000000000000"

-- UTIL --------------------------------------

-- Sotto i 100k si stampa il numero intero: "1830" dice piu' di "1.8K", e a
-- quelle cifre non c'e' problema di spazio. Niente separatore delle migliaia
-- perche' questa stringa usa la virgola come delimitatore fra giocatori.
local function formatNumber(num)
	num = num or 0
	local a = math.abs(num)
	if a >= 1000000 then
		return string.format("%.1fM", num / 1000000)
	elseif a >= 100000 then
		return string.format("%.0fK", num / 1000)
	else
		return string.format("%.0f", num)
	end
end


local function IsPlayer(character)
	if character == nil then
		return false
	end
	return Osi.NRD_CharacterGetInt(character, "IsPlayer") == 1
end

local function SafeStat(stat)
	return math.floor(stat or 0)
end

-- Risolve chi va accreditato per un'azione.
--
-- Verificato in gioco: per un'evocazione NRD_CharacterGetInt(.., "IsPlayer")
-- restituisce 1 e CharacterIsPartyMember pure. Nessuno dei due la distingue
-- dal suo padrone, quindi gli evocati finivano in tabella come riga separata
-- (i vecchi "Summons_OdinAERO_WindElemental_Large_*"). L'unica query che li
-- riconosce e' CharacterIsSummon, e CharacterGetOwner da' l'evocatore.
--
-- Ritorna: guid a cui accreditare (nil = da ignorare), e se veniva da evocato.
-- Gli eventi Osiris NON passano il GUID nudo: passano "NomeTemplate_GUID",
-- p.es. "S_Player_Fane_02a77f1f-872b-49ca-91ab-32098c443beb". NRD_OnHit invece
-- arriva da Ext.ServerEntity.GetGameObject(..).MyGuid, che e' gia' puro.
-- Senza questa normalizzazione tutto cio' che nasce da un listener Osiris
-- (morti, uccisioni, loot, abilita', resurrezioni) veniva scartato perche'
-- lungo diverso da 36, in silenzio.
local DC_NULL_TAIL = "00000000-0000-0000-0000-000000000000"
local GUID_PATTERN = "^%x%x%x%x%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%x%x%x%x%x%x%x%x$"

local function NormalizeGuid(value)
	if type(value) ~= "string" then return nil end
	local tail = (#value == 36) and value or string.sub(value, -36)
	if #tail ~= 36 then return nil end
	if not string.match(tail, GUID_PATTERN) then return nil end
	if tail == DC_NULL_TAIL then return nil end
	return tail
end

local function ResolveActor(rawGuid)
	local guid = NormalizeGuid(rawGuid)
	if guid == nil then
		return nil, false
	end
	local okS, isSummon = pcall(Osi.CharacterIsSummon, guid)
	if okS and isSummon == 1 then
		local okO, owner = pcall(Osi.CharacterGetOwner, guid)
		-- Anche il ritorno di CharacterGetOwner e' in forma Osiris.
		owner = okO and NormalizeGuid(owner) or nil
		if owner ~= nil then
			return owner, true
		end
		-- Evocazione senza padrone (evocata da un nemico, o gia' sparito):
		-- non ha senso accreditarla a nessuno.
		return nil, true
	end
	return guid, false
end

-- DATA --------------------------------------

local function InitializePersistentVars()
	PersistentVars.DamageStats = PersistentVars.DamageStats or {}
end

local function InitializeStatTable()
	return {
		-- DamageDone e Kills sono nostri: prima venivano letti da
		-- player.DamageCounter / player.KillCounter, contatori del motore che
		-- in gioco risultano a zero. Ora li contiamo noi, e sono resettabili.
		DamageDone = 0,
		SummonDamageDone = 0,   -- quota di DamageDone arrivata dagli evocati
		-- Cure contate da noi via BeforeStatusApply (status HEAL di vitalita').
		-- Distinte dal HealCounter del motore, che conta tutta la partita e
		-- non e' resettabile. Limite: i tick di rigenerazione (HEALING) non
		-- passano da un HEAL per tick, quindi qui non compaiono.
		HealingDone = 0,
		HealingReceived = 0,
		-- Fuoco amico. Sono sottoinsiemi di DamageDone / DamageTaken, non si
		-- sommano a parte: servono a dire QUANTA parte del danno e' finita
		-- addosso al gruppo invece che ai nemici.
		AllyDamageDone = 0,
		AllyHitDone = 0,
		AllyDamageTaken = 0,
		SelfDamage = 0,
		Kills = 0,
		DamageTaken = 0,
		Death = 0,
		HitDone = 0,
		HitTaken = 0,
		CriticalHits = 0,
		CriticalDmgDone = 0,
		CriticalHitsTaken = 0,
		CriticalDmgTaken = 0,
		SurfaceDamageDone = 0,
		SurfaceDamageTaken = 0,
		SurfaceHitDone = 0,
		SurfaceHitTaken = 0,
		AttacksMissed = 0,
		MissedAttacks = 0,
		AttackBlocked = 0,
		BlockedAttack = 0,
		ReflectedDamage = 0,
		DamageFromReflection = 0,
		SkillUsed = 0,
		Resurrected = 0,
		DamageSkillUsed = 0,
		DamageSkillDone = 0,
		DamageSkillTaken = 0,
		HighestDamage = 0,
		DestroyedItem = 0,
		StatusDamageDone = 0,
		StatusHitDone = 0,
		StatusDamageTaken = 0,
		StatusHitTaken = 0,
		-- Ripartizione del danno tra armatura (fisica+magica insieme: il
		-- motore da' solo il totale assorbito, hit.Hit.ArmorAbsorption)
		-- e vitalita'.
		DamageToArmour = 0,
		VitalityDamageDone = 0,
		ArmourAbsorbed = 0,
		VitalityDamageTaken = 0,
		-- Controllo (stun, atterramenti, gelo, charm...) andato davvero a segno:
		-- CharacterStatusApplied non scatta per i CC bloccati dall'armatura.
		CCInflicted = 0,
		CCReceived = 0
	}
end

local function EnsureStatsExist(instigator)
	instigator = instigator.MyGuid
    if type(PersistentVars.DamageStats[instigator]) ~= "table" then
        -- Prima creava { HighestDamage = 0 }, cioe' un record con un solo
        -- campo: da li' gli HitDone=nil / DamageTaken=nil visti nella sonda.
        PersistentVars.DamageStats[instigator] = InitializeStatTable()
    end
end

local function clearNonPlayerStats()
    local targetLength = 36  -- La lunghezza desiderata per le chiavi
    local removed, suspect = 0, {}
    for key in pairs(PersistentVars.DamageStats) do
        -- La lunghezza si controlla PRIMA: e' gratis e scarta subito il GUID
        -- nullo (41 caratteri). Prima veniva valutato IsPlayer() per primo,
        -- che su NULL_... fa una query Osiris su un'entita' inesistente e puo'
        -- interrompere l'intera pulizia lasciando la spazzatura in tabella.
        -- Si cancella SOLO cio' che e' strutturalmente invalido: lunghezza
        -- sbagliata o GUID nullo. Non e' recuperabile in nessun caso.
        --
        -- NON si cancella piu' in base a IsPlayer: quella query fallisce anche
        -- quando il personaggio non e' istanziato in quel momento (altra zona,
        -- morto, sessione non ancora pronta), e cancellare li' significa
        -- perdere per sempre le statistiche di un compagno vero.
        if #key ~= targetLength or key == DC_NULL then
            PersistentVars.DamageStats[key] = nil
            removed = removed + 1
        else
            local ok, isPlayer = pcall(IsPlayer, key)
            if ok and not isPlayer then
                table.insert(suspect, key)
            end
        end
    end
    if removed > 0 then
        Ext.Print("[DamageCounter] Rimosse " .. removed .. " voci malformate")
    end
    if #suspect > 0 then
        Ext.Print("[DamageCounter] " .. #suspect .. " voci risultano non-giocante " ..
            "(evocazioni o residui). NON rimosse: potrebbero essere compagni " ..
            "non ancora caricati. Per cancellarle sul serio: !purge_non_player")
        for _, k in ipairs(suspect) do
            Ext.Print("    " .. k)
        end
    end
end

-- Cancellazione esplicita delle voci non-giocante. Separata dalla pulizia
-- automatica proprio perche' e' irreversibile: si lancia a mano, a partita
-- caricata, quando si e' sicuri che il party sia tutto presente.
local function purgeNonPlayerStats()
    local removed, summons = 0, 0
    for key in pairs(PersistentVars.DamageStats) do
        if #key == 36 and key ~= DC_NULL then
            -- Le evocazioni vanno cercate con CharacterIsSummon: su di loro
            -- IsPlayer risponde 1, quindi il solo controllo IsPlayer le
            -- lascerebbe in tabella per sempre. Da ora non ne entrano piu'
            -- di nuove (ResolveActor le accredita al padrone), ma quelle
            -- gia' registrate dalle versioni precedenti restano.
            local okS, isSummon = pcall(Osi.CharacterIsSummon, key)
            local okP, isPlayer = pcall(IsPlayer, key)
            if okS and isSummon == 1 then
                PersistentVars.DamageStats[key] = nil
                summons = summons + 1
            elseif okP and not isPlayer then
                PersistentVars.DamageStats[key] = nil
                removed = removed + 1
            end
        end
    end
    Ext.Print("[DamageCounter] Rimosse " .. summons .. " evocazioni e " ..
        removed .. " voci non-giocante")
end



-- NOTA: clearNonPlayerStats() NON va chiamata qui. Veniva eseguita a ogni
-- aggiornamento (fino a 8 volte per colpo), e ogni giro faceva una query
-- Osiris per ogni voce in tabella. Ora gira una volta sola al caricamento.
local function UpdateStats(character, updates)
	-- Un'evocazione viene accreditata al suo padrone invece che a se stessa:
	-- niente piu' righe separate nel leaderboard, e il danno non sparisce.
	local actor, fromSummon = ResolveActor(character)
	if actor == nil then return end

	local okP, isPlayer = pcall(IsPlayer, actor)
	if not okP or not isPlayer then return end

	-- Accesso diretto per GUID. Prima si scorreva l'intera tabella
	-- confrontando Osi.CharacterGetDisplayName() di ogni voce: due query
	-- Osiris per riga, a ogni aggiornamento, fino a 8 volte per colpo.
	-- C'era anche un Ext.Print() per chiamata che allagava la console.
	local stats = PersistentVars.DamageStats[actor]
	if type(stats) ~= "table" then
		stats = InitializeStatTable()
		PersistentVars.DamageStats[actor] = stats
	end

	for k, v in pairs(updates) do
		stats[k] = SafeStat((stats[k] or 0) + v)
	end

	-- Il danno da evocazione e' gia' finito in DamageDone del padrone qui
	-- sopra; lo teniamo anche a parte per poterlo distinguere.
	if fromSummon and updates.DamageDone then
		stats.SummonDamageDone = SafeStat((stats.SummonDamageDone or 0) + updates.DamageDone)
	end

	-- Segna soltanto: la scrittura su disco e' rimandata e limitata nel tempo.
	-- DC_MarkDirty e' globale ed e' definita piu' sotto nel file; qui viene
	-- risolta a runtime, quando la funzione esiste gia'.
	if DC_MarkDirty then DC_MarkDirty() end
end

-- Come UpdateStats, ma per i contatori indicizzati per tipo di danno
-- (stats.DamageByType / stats.DamageTakenByType): tabelle annidate dentro la
-- voce del personaggio, con le stesse regole di accredito (evocazioni al
-- padrone, solo giocanti).
local function UpdateTypedStats(character, field, additions)
	local actor = ResolveActor(character)
	if actor == nil then return end
	local okP, isPlayer = pcall(IsPlayer, actor)
	if not okP or not isPlayer then return end

	local stats = PersistentVars.DamageStats[actor]
	if type(stats) ~= "table" then
		stats = InitializeStatTable()
		PersistentVars.DamageStats[actor] = stats
	end
	if type(stats[field]) ~= "table" then stats[field] = {} end
	local t = stats[field]
	for k, v in pairs(additions) do
		t[k] = SafeStat((t[k] or 0) + v)
	end

	if DC_MarkDirty then DC_MarkDirty() end
end

-- STATISTICHE PER SKILL ----------------------------------------
-- PersistentVars.SkillStats[guid][skillId] = {Uses, Hits, Damage, ...}.
-- Gli usi arrivano da CharacterUsedSkill, i danni dal ramo skill di
-- DamageControl: stesse fonti delle statistiche aggregate, solo indicizzate
-- per skill. La pagina web le mostra al click sul personaggio.

-- hit.SkillId porta il suffisso di istanza "_-1" (es. "Projectile_Fireball_-1"),
-- mentre CharacterUsedSkill passa l'id pulito: senza normalizzare, la stessa
-- skill farebbe due voci.
local function DC_CleanSkillId(id)
	if id == nil or id == "" then return nil end
	return (tostring(id):gsub("_%-1$", ""))
end

local function UpdateSkillStats(character, skillId, updates)
	if skillId == nil then return end
	local actor = ResolveActor(character)
	if actor == nil then return end
	local okP, isPlayer = pcall(IsPlayer, actor)
	if not okP or not isPlayer then return end

	if type(PersistentVars.SkillStats) ~= "table" then
		PersistentVars.SkillStats = {}
	end
	local byChar = PersistentVars.SkillStats[actor]
	if type(byChar) ~= "table" then
		byChar = {}
		PersistentVars.SkillStats[actor] = byChar
	end
	local s = byChar[skillId]
	if type(s) ~= "table" then
		s = { Uses = 0, Hits = 0, Damage = 0, CritHits = 0, CritDamage = 0, MaxHit = 0 }
		byChar[skillId] = s
	end

	for k, v in pairs(updates) do
		if k == "MaxHit" then
			if v > (s.MaxHit or 0) then s.MaxHit = v end
		else
			s[k] = SafeStat((s[k] or 0) + v)
		end
	end

	if DC_MarkDirty then DC_MarkDirty() end
end

local function LoadSavedData()
	for char, stats in pairs(PersistentVars.DamageStats) do
		for k, v in pairs(InitializeStatTable()) do
			if stats[k] == nil then
				stats[k] = SafeStat(v)
			else
				stats[k] = SafeStat(stats[k])
			end
		end
	end
end

-- FUNCTIONS --------------------------------------

-- === SONDA TEMPORANEA - attribuzione danno delle evocazioni ===
-- Risponde a due domande a cui non sappiamo rispondere leggendo il codice:
--   1) 'instigator' in NRD_OnHit e' l'evocazione, o gia' il suo padrone?
--   2) player.DamageCounter (contatore del MOTORE, non nostro) include gia'
--      il danno delle evocazioni?
-- Se la risposta a (2) e' si', attribuire le evocazioni al padrone nel nostro
-- codice raddoppierebbe i numeri. Da rimuovere a verifica fatta: DC_PROBE = false
DC_PROBE = true

local function DC_ProbeSummonHit(instigatorGuid, hitDamage)
	if not DC_PROBE then return end
	if instigatorGuid == nil or instigatorGuid == DC_NULL then return end
	if type(hitDamage) ~= "number" or hitDamage <= 0 then return end

	-- instigator puo' essere un oggetto (trappola, superficie): le query
	-- su personaggio fallirebbero, quindi tutto sotto pcall.
	local ok, isSummon = pcall(Osi.CharacterIsSummon, instigatorGuid)
	if not ok or isSummon ~= 1 then return end

	local okO, owner = pcall(Osi.CharacterGetOwner, instigatorGuid)
	if not okO then owner = nil end

	local ownerName, ownerDmg = "?", "?"
	if owner ~= nil and owner ~= DC_NULL then
		local okN, n = pcall(Osi.CharacterGetDisplayName, owner)
		if okN and n then ownerName = tostring(n) end
		local okE, e = pcall(Ext.Entity.GetCharacter, owner)
		if okE and e then ownerDmg = tostring(e.DamageCounter) end
	end

	local selfDmg = "?"
	local okS, s = pcall(Ext.Entity.GetCharacter, instigatorGuid)
	if okS and s then selfDmg = tostring(s.DamageCounter) end

	Ext.Print(string.format(
		"[SONDA] colpo di evocazione | danno=%s | evocazione=%s DamageCounter=%s | padrone=%s (%s) DamageCounter=%s",
		tostring(hitDamage), tostring(instigatorGuid), selfDmg,
		tostring(owner), ownerName, ownerDmg))
end

-- Contatori diagnostici. dcHitsSeen conta gli ingressi in DamageControl PRIMA
-- di qualsiasi altra cosa: se resta a zero mentre picchi, l'evento
-- StatusHitEnter non sta arrivando. Se sale ma le statistiche non si muovono,
-- il problema e' piu' avanti. !hitlog stampa il dettaglio di ogni colpo.
dcHitsSeen = 0
dcHitsErrored = 0
dcVanillaHits = 0
dcHandlersRegistered = false
DC_HITLOG = false
dcReflLog = {}   -- ultimi colpi con flag Reflection, mostrati da !dcprobe

-- Legge un flag del colpo dall'oggetto status Lua. I flag (Dodged, Missed,
-- CriticalHit, DoT, ...) sono booleani su hit.Hit (HitDamageInfo): li genera
-- P_BITMASK(EffectFlags) in AllPropertyMaps.inl dell'Extender, e i nomi sono
-- verificati contro la HitFlagMap del sorgente. Prima si leggevano via
-- NRD_StatusGetInt, una query Osiris che non esiste se la story non usa
-- funzioni NRD (vedi la registrazione di StatusHitEnter piu' avanti).
--
-- Se un nome non risolve NON facciamo finta di niente: il flag mancante viene
-- stampato una volta e finisce in dcMissingHitFlags, che !dcprobe mostra.
-- Un fallback muto qui significherebbe contare male in silenzio.
dcMissingHitFlags = {}
local function DC_HitFlag(hit, name)
	local ok, v = pcall(function() return hit.Hit[name] end)
	if ok and v ~= nil then return v == true or v == 1 end
	if not dcMissingHitFlags[name] then
		dcMissingHitFlags[name] = true
		Ext.Print("[DamageCounter] ATTENZIONE: flag '" .. name ..
			"' non trovato su HitDamageInfo: verra' trattato come falso. " ..
			"Le statistiche che dipendono da questo flag NON sono affidabili.")
	end
	return false
end

-- Avvisi una-volta-sola per campi che non risolvono: stessa filosofia di
-- DC_HitFlag, un fallback muto qui conterebbe male in silenzio.
dcMissingDamageFields = {}
local function DC_WarnMissingField(name)
	if not dcMissingDamageFields[name] then
		dcMissingDamageFields[name] = true
		Ext.Print("[DamageCounter] ATTENZIONE: campo '" .. name ..
			"' non leggibile: le statistiche che ne dipendono non sono affidabili.")
	end
end

local function DamageControl(target, instigator, hitDamage, handle, hitStatus)

	dcHitsSeen = dcHitsSeen + 1
	if DC_HITLOG then
		Ext.Print(string.format("[COLPO %d] target=%s instigator=%s danno=%s handle=%s",
			dcHitsSeen, tostring(target), tostring(instigator),
			tostring(hitDamage), tostring(handle)))
	end

	DC_ProbeSummonHit(instigator, hitDamage)

	local target = Ext.ServerEntity.GetGameObject(target) --- @type EsvItem | EsvCharacter
	-- if instigator == 'NULL_00000000-0000-0000-0000-000000000000' then return end
	local instigator = instigator ~= "NULL_00000000-0000-0000-0000-000000000000" and Ext.ServerEntity.GetGameObject(instigator) or {MyGuid = "NULL_00000000-0000-0000-0000-000000000000"} --- @type EsvCharacter|EsvItem
	-- if getmetatable(instigator) ~= "esv::Character" then
	-- 	return
	-- end
	local hit = hitStatus or Ext.ServerEntity.GetStatus(target.MyGuid, handle) --- @type EsvStatusHit
	local skill = hit.SkillId ~= "" and Ext.Stats.Get(hit.SkillId:gsub("(.*).+-1$", "%1")) or nil --- @type StatEntrySkillData | nil
    local Dodged = DC_HitFlag(hit, "Dodged")
    local Missed = DC_HitFlag(hit, "Missed")
    local Critical = DC_HitFlag(hit, "CriticalHit")
    local Backstab = DC_HitFlag(hit, "Backstab")
    local Blocked = DC_HitFlag(hit, "Blocked")
	-- DamageSourceType in Lua e' una stringa enum, non l'intero di NRD:
	-- i valori 1..3 di prima erano le tre varianti di superficie.
	local dst = tostring(hit.DamageSourceType or "")
	local IsSurfaceDamage = dst == "SurfaceMove" or dst == "SurfaceCreate" or dst == "SurfaceStatus"
    local IsDirectAttack = dst == "Attack" or hit.SkillId ~= ""
	local FromReflection = DC_HitFlag(hit, "Reflection")
    local IsWeaponAttack = hit.Hit.HitWithWeapon
	local IsStatusDamage = DC_HitFlag(hit, "DoT")

	if DC_HITLOG then
		-- Seconda riga del log colpo: i flag decodificati e il ramo che verra'
		-- preso. Serve a diagnosticare colpi che "spariscono" (es. riflessione).
		Ext.Print(string.format(
			"  flags: refl=%s dot=%s surf=%s(%s) miss=%s dodge=%s block=%s crit=%s weap=%s skill=%s",
			tostring(FromReflection), tostring(IsStatusDamage), tostring(IsSurfaceDamage), dst,
			tostring(Missed), tostring(Dodged), tostring(Blocked), tostring(Critical),
			tostring(IsWeaponAttack), tostring(hit.SkillId)))
	end

	-- Don't scale damage from surfaces, GM, scriting , reflection, or if the damage type doesn't fit scaling

	if FromReflection and hitDamage > 0 then
		-- Diario degli ultimi colpi riflessi, letto da !dcprobe: la console
		-- dell'Extender silenzia le stampe asincrone mentre sei al prompt,
		-- quindi il log live non basta per diagnosticare questi colpi.
		table.insert(dcReflLog, 1, string.format(
			"target=%s instigator=%s danno=%d",
			tostring(target and target.MyGuid), tostring(instigator and instigator.MyGuid),
			hitDamage))
		if #dcReflLog > 5 then table.remove(dcReflLog) end
		if instigator ~= nil and instigator ~= "NULL_00000000-0000-0000-0000-000000000000" then
			UpdateStats(instigator.MyGuid, {ReflectedDamage = hitDamage})
		end
		if target ~= nil and target ~= "NULL_00000000-0000-0000-0000-000000000000" then
			UpdateStats(target.MyGuid, {DamageFromReflection = hitDamage})
		end
	end

	if Missed then
		UpdateStats(instigator.MyGuid, {AttacksMissed = 1})
		UpdateStats(target.MyGuid, {MissedAttacks = 1})
	end

	if Blocked then
		UpdateStats(instigator.MyGuid, {AttackBlocked = 1})
		UpdateStats(target.MyGuid, {BlockedAttack = 1})
	end

	if IsSurfaceDamage and hitDamage > 0 then
		UpdateStats(instigator.MyGuid, {SurfaceDamageDone = hitDamage})
		UpdateStats(instigator.MyGuid, {SurfaceHitDone = 1})
		UpdateStats(target.MyGuid, {SurfaceDamageTaken = hitDamage})
		UpdateStats(target.MyGuid, {SurfaceHitTaken = 1})
	elseif IsStatusDamage and not IsDirectAttack then
		-- Gli status di cura passano di qui con hitDamage negativo: sommarli
		-- scaverebbe il totale sotto zero. Clamp sulle somme, non sui conteggi.
		local dmg = math.max(0, hitDamage or 0)
		UpdateStats(instigator.MyGuid, {StatusDamageDone = dmg})
		UpdateStats(instigator.MyGuid, {StatusHitDone = 1})
		UpdateStats(target.MyGuid, {StatusDamageTaken = dmg})
		UpdateStats(target.MyGuid, {StatusHitTaken = 1})
	else
		UpdateStats(instigator.MyGuid, {HitDone = 1})
		UpdateStats(target.MyGuid, {HitTaken = 1})
	end

	if Critical and hitDamage > 0 then
		UpdateStats(instigator.MyGuid, {CriticalHits = 1})
		UpdateStats(instigator.MyGuid, {CriticalDmgDone = hitDamage})
		UpdateStats(target.MyGuid, {CriticalHitsTaken = 1})
		UpdateStats(target.MyGuid, {CriticalDmgTaken = hitDamage})
	end

	if skill ~= nil then
		if hitDamage > 0 then
			UpdateStats(instigator.MyGuid, {DamageSkillUsed = 1})
			UpdateStats(instigator.MyGuid, {DamageSkillDone = hitDamage})
			UpdateStats(target.MyGuid, {DamageSkillTaken = hitDamage})
			-- Dettaglio per singola skill (pagina web, click sul personaggio).
			local skillKey = DC_CleanSkillId(hit.SkillId)
			local upd = { Hits = 1, Damage = hitDamage, MaxHit = hitDamage }
			if Critical then
				upd.CritHits = 1
				upd.CritDamage = hitDamage
			end
			UpdateSkillStats(instigator.MyGuid, skillKey, upd)
		end
	end

	if hitDamage > 0 then
		-- HighestDamage scriveva diretto in tabella saltando UpdateStats, e
		-- quindi anche il controllo IsPlayer: il danno da superficie/ambiente
		-- (instigator = NULL_...) creava una voce fantasma con dentro solo
		-- questo campo. Ora si aggiorna solo per giocanti reali.
		local ig = instigator.MyGuid
		local actor, fromSummon = ResolveActor(ig)
		if actor ~= nil then
			local okP, isP = pcall(IsPlayer, actor)
			-- HighestDamage = colpo singolo piu' forte messo a segno DI PERSONA.
			-- I colpi degli evocati sono esclusi di proposito: confluiscono in
			-- DamageDone e SummonDamageDone del padrone, ma non gli intestano un
			-- record che non ha tirato lui. Per includerli, togliere fromSummon.
			if okP and isP and not fromSummon then
				if type(PersistentVars.DamageStats[actor]) ~= "table" then
					PersistentVars.DamageStats[actor] = InitializeStatTable()
				end
				local cur = PersistentVars.DamageStats[actor]["HighestDamage"] or 0
				if hitDamage > cur then
					PersistentVars.DamageStats[actor]["HighestDamage"] = hitDamage
				end
			end
			-- UpdateStats risolve di nuovo l'evocazione sul padrone.
			UpdateStats(ig, {DamageDone = hitDamage})
		end
		UpdateStats(target.MyGuid, {DamageTaken = hitDamage})

		-- FUOCO AMICO. Il bersaglio viene risolto come l'attaccante, cosi' il
		-- danno preso da un evocato finisce al suo padrone e i due lati della
		-- stessa botta restano coerenti.
		local tgtActor = ResolveActor(target.MyGuid)
		if actor ~= nil and tgtActor ~= nil then
			if actor == tgtActor then
				-- Auto-danno: la propria superficie, il proprio contraccolpo.
				-- Tenuto separato, altrimenti gonfierebbe il fuoco amico.
				UpdateStats(actor, {SelfDamage = hitDamage})
			else
				local okA, aParty = pcall(Osi.CharacterIsPartyMember, actor)
				local okT, tParty = pcall(Osi.CharacterIsPartyMember, tgtActor)
				if okA and okT and aParty == 1 and tParty == 1 then
					UpdateStats(actor,    {AllyDamageDone = hitDamage, AllyHitDone = 1})
					UpdateStats(tgtActor, {AllyDamageTaken = hitDamage})
				end
			end
		end

		-- DANNI PER TIPO + ARMATURA/VITALITA' + RESISTENZE. Tutto viene dal
		-- DamageList del colpo, che porta i danni finali gia' separati per tipo.
		local okDL, dlist = pcall(function() return hit.Hit.DamageList:ToTable() end)
		if not okDL or type(dlist) ~= "table" then
			DC_WarnMissingField("Hit.DamageList")
		else
			local byType = {}
			for _, d in ipairs(dlist) do
				local dt = tostring(d.DamageType)
				local amt = math.floor(tonumber(d.Amount) or 0)
				if amt > 0 then
					byType[dt] = (byType[dt] or 0) + amt
				end
			end

			if next(byType) ~= nil then
				UpdateTypedStats(instigator.MyGuid, "DamageByType", byType)
				UpdateTypedStats(target.MyGuid, "DamageTakenByType", byType)
			end

			-- Quota del colpo mangiata dall'armatura (fisica+magica insieme:
			-- il motore da' solo il totale assorbito) e quota alla vitalita'.
			local okAA, absorbed = pcall(function() return hit.Hit.ArmorAbsorption end)
			if not okAA or type(absorbed) ~= "number" then
				DC_WarnMissingField("Hit.ArmorAbsorption")
				absorbed = 0
			end
			absorbed = math.max(0, math.min(math.floor(absorbed), hitDamage))
			local toVitality = hitDamage - absorbed

			UpdateStats(instigator.MyGuid,
				{ VitalityDamageDone = toVitality, DamageToArmour = absorbed })
			UpdateStats(target.MyGuid,
				{ VitalityDamageTaken = toVitality, ArmourAbsorbed = absorbed })
		end
	end
end

-- L'evento Osiris NRD_OnHit qui NON arriva mai da solo: il compilatore Osiris
-- scarta gli eventi che nessuna regola story usa, e questa mod e' solo Lua.
-- Nella story di DamageCounter NRD_OnHit e' dichiarato ma mai referenziato,
-- quindi il nodo non esiste e l'Extender non ha dove dispatcharlo. Con Epip o
-- LeaderLib attivi funzionava perche' le LORO story usano funzioni NRD e
-- portavano il nodo nella story fusa (il RequiredExtensionVersion non c'entrava).
-- StatusHitEnter e' l'equivalente Lua nativo (Extender v56+): stessa semantica
-- di NRD_OnHit, nessuna dipendenza dalla story ne' da altre mod.
--
-- DamageControl gira sotto pcall: se un colpo particolare fa saltare qualcosa
-- (un instigator inatteso, uno status non recuperabile), l'errore viene
-- stampato invece di far sparire il colpo senza lasciare traccia. Prima un
-- singolo caso non gestito bastava a non far salire piu' nulla, in silenzio.
dcHitEventStatus = "non registrato"
local okSub, errSub = pcall(function()
	Ext.Events.StatusHitEnter:Subscribe(function (e)
		local status = e.Hit --- @type EsvStatusHit
		if status == nil then return end
		local okT, targetObj = pcall(Ext.ServerEntity.GetGameObject, status.TargetHandle)
		if not okT or targetObj == nil then return end
		local okS, srcObj = pcall(Ext.ServerEntity.GetGameObject, status.StatusSourceHandle)
		local instGuid = (okS and srcObj ~= nil) and srcObj.MyGuid
			or "NULL_00000000-0000-0000-0000-000000000000"
		-- Sui colpi da riflessione il motore lascia StatusSourceHandle vuoto
		-- (verificato con !dcprobe: instigator=NULL), quindi ReflectedDamage
		-- non sapeva a chi andare. Il PendingHit dell'evento pero' cattura
		-- l'attaccante nella fase esv::Character::Hit: da li' si recupera il
		-- riflettente. Vale anche per ogni altro colpo senza sorgente.
		if instGuid == "NULL_00000000-0000-0000-0000-000000000000" and e.Context ~= nil then
			local okA, atk = pcall(Ext.ServerEntity.GetGameObject, e.Context.AttackerHandle)
			if okA and atk ~= nil then
				instGuid = atk.MyGuid
			end
		end
		local dmg = (status.Hit and status.Hit.TotalDamageDone) or 0
		local ok, err = pcall(DamageControl, targetObj.MyGuid, instGuid, dmg,
			status.StatusHandle, status)
		if not ok then
			dcHitsErrored = dcHitsErrored + 1
			if dcHitsErrored <= 5 then
				Ext.Print("[DamageCounter] ERRORE nel colpo #" .. dcHitsSeen .. ": " .. tostring(err))
			elseif dcHitsErrored == 6 then
				Ext.Print("[DamageCounter] (altri errori sui colpi non verranno stampati)")
			end
		end
	end)
end)
dcHitEventStatus = okSub and "ok" or ("FALLITO: " .. tostring(errSub))
if not okSub then
	Ext.Print("[DamageCounter] impossibile agganciare StatusHitEnter: " .. tostring(errSub))
end

-- CURE. Non esiste un evento Lua "StatusHealEnter": BeforeStatusApply passa
-- ogni status prima dell'applicazione, e li' si filtra HEAL di vitalita'.
-- (L'equivalente Osiris, NRD_OnHeal, ha lo stesso problema di story di
-- NRD_OnHit: mai referenziato, mai dispatchato.)
dcHealsSeen = 0
local okHeal, errHeal = pcall(function()
	Ext.Events.BeforeStatusApply:Subscribe(function (e)
		local status = e.Status
		if status == nil or tostring(status.StatusType) ~= "HEAL" then return end
		-- Solo vitalita': i "heal" di armatura fisica/magica sono ripristini
		-- di scudo e gonfierebbero il numero che la gente si aspetta.
		if tostring(status.HealType) ~= "Vitality" then return end
		local amount = tonumber(status.HealAmount) or 0
		if amount <= 0 then return end
		dcHealsSeen = dcHealsSeen + 1
		local okT, targetObj = pcall(Ext.ServerEntity.GetGameObject, status.TargetHandle)
		local okS, srcObj = pcall(Ext.ServerEntity.GetGameObject, status.StatusSourceHandle)
		if okS and srcObj ~= nil then
			UpdateStats(srcObj.MyGuid, { HealingDone = amount })
		end
		if okT and targetObj ~= nil then
			UpdateStats(targetObj.MyGuid, { HealingReceived = amount })
		end
	end)
end)
dcHealEventStatus = okHeal and "ok" or ("FALLITO: " .. tostring(errHeal))
if not okHeal then
	Ext.Print("[DamageCounter] impossibile agganciare BeforeStatusApply (cure): " .. tostring(errHeal))
end


local function ResetStats()
	Ext.Print("resetting stats...")
	PersistentVars.DamageStats = {}
	PersistentVars.SkillStats = {}
	PersistentVars.Fights = {}
end

local function formatName(name)
    local maxLength = 5
    if #name > maxLength then
        return string.sub(name, 1, maxLength)  -- Tronca il nome se è più lungo di 5 caratteri
    else
        return name .. string.rep("", maxLength - #name)  -- Aggiungi puntini se il nome è più corto
    end
end

local function nonNegative(value)
    return math.max(0, value or 0)
end

-- I chiamanti passano gia' un primo argomento (a volte nil, a volte un GUID)
-- che la funzione non ha mai usato: lo si assorbe con _ per non cambiarli.
local function ShowConsoleLeaderboard(_, verbose)
    local names = {}
	local DamageCounter = {}
	local SummonDamageDone = {}
	local AllyDamageDone = {}
	local AllyHitDone = {}
	local AllyDamageTaken = {}
	local SelfDamage = {}
	local DamageTaken = {}
	local HealingDone = {}
	local KillCounter = {}
	local Death = {}
	local HitDone = {}
	local HitTaken = {}
	local CriticalHits = {}
	local CriticalDmgDone = {}
	local CriticalHitsTaken = {}
	local CriticalDmgTaken = {}
	local SurfaceDamageDone = {}
	local SurfaceDamageTaken = {}
	local SurfaceHitDone = {}
	local SurfaceHitTaken = {}
	local AttacksMissed = {}
	local MissedAttacks = {}
	local AttackBlocked = {}
	local BlockedAttack = {}
	local DamageFromReflection = {}
	local ReflectedDamage = {}
	local SkillUsed = {}
	local Resurrected = {}
	local DamageSkillUsed = {}
	local DamageSkillDone = {}
	local DamageSkillTaken = {}
	local HighestDamage = {}
	local DestroyedItem = {}
	local kda = {}
	local critRate = {}
	local missRate = {}
	local avgDam = {}
	local LootedCorpses = {}
	local StatusDamageDone = {}
	local StatusHitDone = {}
	local StatusDamageTaken = {}
	local StatusHitTaken = {}

    for character, stats in pairs(PersistentVars.DamageStats) do
		local player = Ext.Entity.GetCharacter(character)
		-- Prima il filtro era su CharacterGetReservedUserID, cioe' l'ID del
		-- giocatore umano che ha preso quel personaggio. I compagni non
		-- assegnati a nessuno (tutti, in singolo) non ce l'hanno e sparivano
		-- dal leaderboard pur avendo le statistiche registrate.
		-- CharacterIsPartyMember include l'intero gruppo.
		if player ~= nil and Osi.CharacterIsPartyMember(character) == 1 then
			local name = Osi.CharacterGetDisplayName(character)
			local displayName = formatName(Ext.L10N.GetTranslatedString(name, "failed"))

			table.insert(names, displayName)
			-- Prima queste tre venivano da player.* (contatori del motore).
			-- DamageCounter e KillCounter risultavano a zero in gioco, e con
			-- loro anche kda e avgDam che ci dividono sopra. Ora sono nostri.
			table.insert(DamageCounter, formatNumber(nonNegative(stats.DamageDone)))
			table.insert(SummonDamageDone, formatNumber(nonNegative(stats.SummonDamageDone)))
			table.insert(AllyDamageDone, formatNumber(nonNegative(stats.AllyDamageDone)))
			table.insert(AllyHitDone, formatNumber(nonNegative(stats.AllyHitDone)))
			table.insert(AllyDamageTaken, formatNumber(nonNegative(stats.AllyDamageTaken)))
			table.insert(SelfDamage, formatNumber(nonNegative(stats.SelfDamage)))
			table.insert(DamageTaken, formatNumber(nonNegative(stats.DamageTaken)))
			-- HealingDone resta dal motore: non abbiamo un evento cure da
			-- agganciare. Se anche questo legge 0, va tracciato a parte.
			table.insert(HealingDone, formatNumber(nonNegative(player.HealCounter)))
			table.insert(KillCounter, formatNumber(nonNegative(stats.Kills)))
			table.insert(Death, formatNumber(nonNegative(stats.Death)))
			table.insert(HitDone, formatNumber(nonNegative(stats.HitDone)))
			table.insert(HitTaken, formatNumber(nonNegative(stats.HitTaken)))
			table.insert(CriticalHits, formatNumber(nonNegative(stats.CriticalHits)))
			table.insert(CriticalDmgDone, formatNumber(nonNegative(stats.CriticalDmgDone)))
			table.insert(CriticalHitsTaken, formatNumber(nonNegative(stats.CriticalHitsTaken)))
			table.insert(CriticalDmgTaken, formatNumber(nonNegative(stats.CriticalDmgTaken)))
			table.insert(SurfaceDamageDone, formatNumber(nonNegative(stats.SurfaceDamageDone)))
			table.insert(SurfaceDamageTaken, formatNumber(nonNegative(stats.SurfaceDamageTaken)))
			table.insert(SurfaceHitDone, formatNumber(nonNegative(stats.SurfaceHitDone)))
			table.insert(SurfaceHitTaken, formatNumber(nonNegative(stats.SurfaceHitTaken)))
			table.insert(AttacksMissed, formatNumber(nonNegative(stats.AttacksMissed)))
			table.insert(MissedAttacks, formatNumber(nonNegative(stats.MissedAttacks)))
			table.insert(AttackBlocked, formatNumber(nonNegative(stats.AttackBlocked)))
			table.insert(BlockedAttack, formatNumber(nonNegative(stats.BlockedAttack)))
			table.insert(ReflectedDamage, formatNumber(nonNegative(stats.ReflectedDamage)))
			table.insert(DamageFromReflection, formatNumber(nonNegative(stats.DamageFromReflection)))
			table.insert(SkillUsed, formatNumber(nonNegative(stats.SkillUsed)))
			table.insert(Resurrected, formatNumber(nonNegative(stats.Resurrected)))
			table.insert(DamageSkillUsed, formatNumber(nonNegative(stats.DamageSkillUsed)))
			table.insert(DamageSkillDone, formatNumber(nonNegative(stats.DamageSkillDone)))
			table.insert(DamageSkillTaken, formatNumber(nonNegative(stats.DamageSkillTaken)))
			table.insert(HighestDamage, formatNumber(nonNegative(stats.HighestDamage)))
			table.insert(DestroyedItem, formatNumber(nonNegative(stats.DestroyedItem)))
			local kills = nonNegative(stats.Kills)
			table.insert(kda, (stats.Death > 0 and kills > 0 and string.format("%.1f", kills / stats.Death) or "0"))
			table.insert(critRate, 
				(stats.HitDone > 0 and 
					((stats.CriticalHits / stats.HitDone) * 100 >= 100 and "100" or string.format("%.0f%%", (stats.CriticalHits / stats.HitDone) * 100))
				or "0%")
			)

			table.insert(missRate, 
				(stats.HitDone > 0 and 
					((stats.AttacksMissed / stats.HitDone) * 100 >= 100 and "100" or string.format("%.0f%%", (stats.AttacksMissed / stats.HitDone) * 100))
				or "0%")
			)
			table.insert(avgDam, (stats.HitDone > 0 and formatNumber(nonNegative(stats.DamageDone) / stats.HitDone) or "0"))
			table.insert(LootedCorpses, formatNumber(stats.LootedCorpses))
			table.insert(StatusDamageDone, formatNumber(nonNegative(stats.StatusDamageDone)))
			table.insert(StatusHitDone, formatNumber(nonNegative(stats.StatusHitDone)))
			table.insert(StatusDamageTaken, formatNumber(nonNegative(stats.StatusDamageTaken)))
			table.insert(StatusHitTaken, formatNumber(nonNegative(stats.StatusHitTaken)))

		end
	end

    if #names == 0 then
		Ext.Print("Nothing to show, no names has been found")
		return
	end

	local messageLines = {
		names,
		DamageCounter,
		DamageTaken,
		HealingDone,
		KillCounter,
		Death,
		HitDone,
		HitTaken,
		CriticalHits,
		CriticalDmgDone,
		CriticalHitsTaken,
		CriticalDmgTaken,
		SurfaceDamageDone,
		SurfaceDamageTaken,
		SurfaceHitDone,
		SurfaceHitTaken,
		StatusDamageDone,
		StatusHitDone,
		StatusDamageTaken,
		StatusHitTaken,
		AttacksMissed,
		MissedAttacks,
		AttackBlocked,
		BlockedAttack,
		DamageFromReflection,
		DamageSkillUsed,
		DamageSkillDone,
		DamageSkillTaken,
		HighestDamage,
		kda,
		critRate,
		missRate,
		avgDam,
		DestroyedItem,
		LootedCorpses,
		-- Queste quattro erano raccolte ma mai messe in colonna: ReflectedDamage
		-- e SkillUsed esistevano da sempre, SummonDamageDone e Resurrected sono
		-- nuove. Aggiunte in fondo perche' le posizioni contano.
		SummonDamageDone,
		ReflectedDamage,
		SkillUsed,
		Resurrected,
		AllyDamageDone,
		AllyHitDone,
		AllyDamageTaken,
		SelfDamage
	}

	-- Etichette in un elenco PARALLELO a messageLines. Sono la stessa cosa
	-- dichiarata due volte, il che e' esattamente il difetto: basta aggiungere
	-- o togliere una voce da una parte sola e tutto quello che legge la stringa
	-- si sfasa in silenzio. Il controllo sotto rende il disallineamento
	-- rumoroso invece che invisibile.
	local labels = {
		"Nome", "DamageDone", "DamageTaken", "HealingDone", "Kills", "Death",
		"HitDone", "HitTaken", "CriticalHits", "CriticalDmgDone",
		"CriticalHitsTaken", "CriticalDmgTaken", "SurfaceDamageDone",
		"SurfaceDamageTaken", "SurfaceHitDone", "SurfaceHitTaken",
		"StatusDamageDone", "StatusHitDone", "StatusDamageTaken",
		"StatusHitTaken", "AttacksMissed", "MissedAttacks", "AttackBlocked",
		"BlockedAttack", "DamageFromReflection", "DamageSkillUsed",
		"DamageSkillDone", "DamageSkillTaken", "HighestDamage", "kda",
		"critRate", "missRate", "avgDam", "DestroyedItem", "LootedCorpses",
		"SummonDamageDone", "ReflectedDamage", "SkillUsed", "Resurrected",
		"AllyDamageDone", "AllyHitDone", "AllyDamageTaken", "SelfDamage"
	}

	local serializedData = {}
	for _, line in ipairs(messageLines) do
		table.insert(serializedData, table.concat(line, ","))
	end
	local dataString = table.concat(serializedData, "@")

	if verbose then
		Ext.Print(string.format("--- %d colonne dichiarate, %d serializzate, %d etichette, %d personaggi ---",
			#messageLines, #serializedData, #labels, #names))
		if #serializedData ~= #labels then
			Ext.Print("  !!! DISALLINEAMENTO: le etichette non corrispondono alle colonne")
		end
		for i, v in ipairs(serializedData) do
			Ext.Print(string.format("  %2d  %-22s %s", i, labels[i] or "???", v))
		end
	end

	return dataString
end

-- EXPORT JSON ----------------------------------------
-- Scrive le statistiche su file per la pagina web. Il file finisce in
--   Documents\Larian Studios\DOS2 DE\Osiris Data\DamageCounter_Stats.json
-- che e' la cartella dove Ext.IO.SaveFile scrive di default (le altre mod
-- installate ci mettono i loro json allo stesso modo).

local DC_EXPORT_FILE = "DamageCounter_Stats.json"          -- sempre l'ultimo stato
-- Un file per run, dentro sottocartelle per profilo. Le sottocartelle
-- funzionano: Epip usa lo stesso schema per le sue impostazioni
-- ("Epip/Settings/<profilo>/<modulo>.json").
local DC_RUN_FILE_FMT = "DamageCounter/%s/%s.json"

-- Identificatore della run. Generato UNA volta e conservato nei PersistentVars,
-- che vivono dentro il salvataggio: viaggia con lui e distingue una partita
-- dall'altra senza dipendere da API di cui non conosco la disponibilita'.
-- Nota: due rami dello stesso salvataggio condividono l'id, per costruzione.
local function DC_Now()
	if Ext.Utils and type(Ext.Utils.MonotonicTime) == "function" then
		return Ext.Utils.MonotonicTime()
	end
	-- 'os' non esiste nel sandbox dell'Extender: niente os.time() come ripiego.
	return 0
end

-- math.randomseed (e forse math.random) sono bloccati dal sandbox: LCG
-- fatto in casa (costanti di Numerical Recipes), seminato da DC_Now().
local dcRngState = nil
local function DC_Rand16()
	if not dcRngState then
		dcRngState = DC_Now() % 2147483647
		if dcRngState == 0 then dcRngState = 42 end
	end
	dcRngState = (dcRngState * 1664525 + 1013904223) % 4294967296
	-- i bit alti sono i piu' "mescolati" in un LCG
	return math.floor(dcRngState / 268435456) % 16
end

local function DC_RunId()
	if not PersistentVars.RunId then
		-- DC_Now() e' MonotonicTime dell'Extender: cambia tra un avvio e
		-- l'altro, quindi due partite non ricevono la stessa base.
		local r = ""
		for _ = 1, 12 do r = r .. string.format("%x", DC_Rand16()) end
		PersistentVars.RunId = string.format("%d-%s", DC_Now(), r)
	end
	return PersistentVars.RunId
end

-- PER-FIGHT ------------------------------------------------------
-- Fotografia delle stats dei giocatori a inizio combattimento e differenza
-- alla fine: il tracking normale non viene toccato, la fight e' solo una
-- finestra sui contatori che gia' esistono. Lo snapshot vive in RAM: salvare
-- e ricaricare A META' scontro perde la registrazione di QUELLO scontro
-- (i totali restano comunque giusti).
local DC_MAX_FIGHTS = 50   -- le fight vivono nel savegame: cap anti-gonfiaggio
local dcCombatSnapshots = {}   -- combatId -> { startedAt, stats = {guid -> copia} }
local dcCombatEnemies = {}     -- combatId -> { guid -> nome }: chi c'era contro

local function DC_CopyStats(stats)
	local copy = {}
	for k, v in pairs(stats) do
		if type(v) == "table" then
			local sub = {}
			for k2, v2 in pairs(v) do sub[k2] = v2 end
			copy[k] = sub
		else
			copy[k] = v
		end
	end
	return copy
end

-- Differenza corrente - snapshot. I contatori si sottraggono; HighestDamage
-- e' un massimo, non un contatore: entra nel delta solo se il record e'
-- stato battuto durante lo scontro.
local function DC_DiffStats(cur, snap)
	local diff, any = {}, false
	for k, v in pairs(cur) do
		if type(v) == "table" then
			local sub, subAny = {}, false
			local snapSub = type(snap[k]) == "table" and snap[k] or {}
			for k2, v2 in pairs(v) do
				local d = SafeStat(v2) - SafeStat(snapSub[k2])
				if d > 0 then
					sub[k2] = d
					subAny = true
				end
			end
			if subAny then
				diff[k] = sub
				any = true
			end
		elseif type(v) == "number" then
			if k == "HighestDamage" then
				if v > SafeStat(snap[k]) then
					diff[k] = v
					any = true
				end
			else
				local d = SafeStat(v) - SafeStat(snap[k])
				if d > 0 then
					diff[k] = d
					any = true
				end
			end
		end
	end
	return diff, any
end

local function DC_TranslatedName(guid)
	local okN, handle = pcall(Osi.CharacterGetDisplayName, guid)
	if not okN or handle == nil or handle == "" then return nil end
	local okT, tr = pcall(Ext.L10N.GetTranslatedString, handle, handle)
	return (okT and tr ~= nil and tr ~= "") and tr or handle
end

-- Nome tradotto e icona di una skill dal suo stat entry. Usato sia dal
-- payload generale sia dal dettaglio per-fight.
local function DC_SkillMeta(skillId)
	local name, icon = skillId, nil
	local okS, statEntry = pcall(Ext.Stats.Get, skillId)
	if okS and statEntry ~= nil then
		local okI, ic = pcall(function() return statEntry.Icon end)
		if okI then icon = ic end
		local okD, dn = pcall(function() return statEntry.DisplayName end)
		if okD and dn ~= nil and dn ~= "" then
			local okT, tr = pcall(Ext.L10N.GetTranslatedStringFromKey, dn)
			if not okT or tr == nil or tr == "" then
				okT, tr = pcall(Ext.L10N.GetTranslatedString, dn, "")
			end
			if okT and tr ~= nil and tr ~= "" then name = tr end
		end
	end
	return name, icon
end

-- Differenza per-skill (stessa logica di DC_DiffStats, sui contatori delle
-- SkillStats). MaxHit e' un massimo: nel delta entra solo se il record e'
-- stato battuto durante lo scontro, altrimenti resta assente ("-" in pagina).
local function DC_DiffSkills(curByS, snapByS)
	local out = {}
	for id, s in pairs(curByS or {}) do
		local sn = (snapByS or {})[id] or {}
		local uses = SafeStat(s.Uses) - SafeStat(sn.Uses)
		local hits = SafeStat(s.Hits) - SafeStat(sn.Hits)
		local dmg  = SafeStat(s.Damage) - SafeStat(sn.Damage)
		if uses > 0 or hits > 0 or dmg > 0 then
			local name, icon = DC_SkillMeta(id)
			local entry = {
				id = id, name = name, icon = icon,
				uses = uses, hits = hits, damage = dmg,
				critHits = SafeStat(s.CritHits) - SafeStat(sn.CritHits),
				critDamage = SafeStat(s.CritDamage) - SafeStat(sn.CritDamage),
			}
			if SafeStat(s.MaxHit) > SafeStat(sn.MaxHit) then
				entry.maxHit = SafeStat(s.MaxHit)
			end
			table.insert(out, entry)
		end
	end
	table.sort(out, function(a, b) return a.damage > b.damage end)
	return out
end

local function DC_OnEnteredCombat(objectGuid, combatId)
	local guid = NormalizeGuid(objectGuid)
	if guid == nil then return end

	-- Non-giocatore e non-evocazione = nemico (o NPC trascinato dentro):
	-- se ne registra il nome per il "chi c'era" della fight. Dedup per guid,
	-- cosi' rientrare in combattimento non lo conta due volte.
	local okP, isP = pcall(IsPlayer, guid)
	if okP and not isP then
		local okS, isSummon = pcall(Osi.CharacterIsSummon, guid)
		if not okS or isSummon ~= 1 then
			local name = DC_TranslatedName(guid)
			if name ~= nil then
				local en = dcCombatEnemies[combatId]
				if en == nil then
					en = {}
					dcCombatEnemies[combatId] = en
				end
				en[guid] = name
			end
		end
		return
	end

	local actor = ResolveActor(guid)
	if actor == nil then return end
	local okA, isA = pcall(IsPlayer, actor)
	if not okA or not isA then return end

	local snap = dcCombatSnapshots[combatId]
	if snap == nil then
		snap = { startedAt = DC_Now(), stats = {}, skills = {} }
		dcCombatSnapshots[combatId] = snap
	end
	-- Alla prima entrata di un giocatore si fotografano TUTTI i personaggi
	-- conosciuti; chi compare in tabella solo dopo (primo colpo della sua
	-- vita) alla fine viene confrontato con uno snapshot vuoto, che per un
	-- personaggio appena nato e' la fotografia giusta.
	for guid, stats in pairs(PersistentVars.DamageStats or {}) do
		if snap.stats[guid] == nil and type(stats) == "table" then
			snap.stats[guid] = DC_CopyStats(stats)
		end
	end
	for guid, byS in pairs(PersistentVars.SkillStats or {}) do
		if snap.skills[guid] == nil and type(byS) == "table" then
			local c = {}
			for id, s in pairs(byS) do
				local sc = {}
				for k, v in pairs(s) do sc[k] = v end
				c[id] = sc
			end
			snap.skills[guid] = c
		end
	end
end

local function DC_OnCombatEnded(combatId)
	local snap = dcCombatSnapshots[combatId]
	dcCombatSnapshots[combatId] = nil
	local enemySeen = dcCombatEnemies[combatId]
	dcCombatEnemies[combatId] = nil
	if snap == nil then return end

	local playersOut = {}
	for guid, stats in pairs(PersistentVars.DamageStats or {}) do
		if type(stats) == "table" then
			local diff, any = DC_DiffStats(stats, snap.stats[guid] or {})
			if any then
				table.insert(playersOut, {
					guid = guid,
					name = DC_TranslatedName(guid) or guid,
					stats = diff,
					skills = DC_DiffSkills(
						(PersistentVars.SkillStats or {})[guid],
						(snap.skills or {})[guid]),
				})
			end
		end
	end
	-- Scontro in cui nessun giocatore ha mosso un numero: non vale un posto
	-- nella lista (e nel savegame).
	if #playersOut == 0 then return end

	table.sort(playersOut, function(a, b)
		return (a.stats.DamageDone or 0) > (b.stats.DamageDone or 0)
	end)

	local region
	local okH, host = pcall(Osi.CharacterGetHostCharacter)
	if okH and host ~= nil then
		local okR, r = pcall(Osi.GetRegion, host)
		if okR and r ~= nil and r ~= "" then region = r end
	end

	-- Nemici aggregati per nome: {name = "Voidwoken", n = 2}, dal piu'
	-- numeroso. L'array (non una mappa) preserva l'ordine nel JSON.
	local enemies = {}
	if enemySeen ~= nil then
		local counts = {}
		for _, name in pairs(enemySeen) do
			counts[name] = (counts[name] or 0) + 1
		end
		for name, n in pairs(counts) do
			table.insert(enemies, { name = name, n = n })
		end
		table.sort(enemies, function(a, b)
			if a.n ~= b.n then return a.n > b.n end
			return a.name < b.name
		end)
	end

	-- Niente data reale qui: il sandbox dell'Extender non espone os.time e
	-- DC_Now() e' tempo monotonico (buono per la durata, non per "quando").
	-- La data la assegna il server web al primo avvistamento della fight.
	if type(PersistentVars.Fights) ~= "table" then PersistentVars.Fights = {} end
	local fights = PersistentVars.Fights
	table.insert(fights, {
		combatId = combatId,
		startedAt = snap.startedAt,
		endedAt = DC_Now(),
		region = region,
		players = playersOut,
		enemies = enemies,
	})
	while #fights > DC_MAX_FIGHTS do table.remove(fights, 1) end
	if DC_MarkDirty then DC_MarkDirty() end
end

-- Profilo del giocatore che controlla un personaggio, via
-- personaggio -> ID utente -> profilo. Tutte query server-side.
local function DC_ProfileOf(guid)
	local okU, userId = pcall(Osi.CharacterGetReservedUserID, guid)
	if not okU or userId == nil or userId == 0 then return nil, nil, nil end
	local okP, profileId = pcall(Osi.GetUserProfileID, userId)
	local okN, userName = pcall(Osi.GetUserName, userId)
	return userId, (okP and profileId or nil), (okN and userName or nil)
end
local DC_EXPORT_MIN_INTERVAL = 2000   -- millisecondi tra due scritture
local dcDirty = false
local dcLastExport = 0

-- Il nome dell'API e' cambiato tra le versioni dell'Extender: nelle piu'
-- recenti e' Ext.IO.SaveFile, nelle vecchie Ext.SaveFile.
local function DC_WriteFile(name, contents)
	if Ext.IO and type(Ext.IO.SaveFile) == "function" then
		Ext.IO.SaveFile(name, contents)
		return "Ext.IO.SaveFile"
	elseif type(Ext.SaveFile) == "function" then
		Ext.SaveFile(name, contents)
		return "Ext.SaveFile"
	end
	return nil
end

local function DC_BuildPayload()
	local players = {}

	-- Personaggio dell'host: serve per marcare isHost e per scegliere il
	-- profilo "proprietario" della run in modo deterministico. L'Osiris
	-- restituisce il guid con prefisso di nome: si tengono gli ultimi 36
	-- caratteri, lo stesso formato delle chiavi di DamageStats.
	local hostGuid
	local okH, host = pcall(Osi.CharacterGetHostCharacter)
	if okH and type(host) == "string" and #host >= 36 then
		hostGuid = string.sub(host, -36)
	end
	for guid, stats in pairs(PersistentVars.DamageStats or {}) do
		if #guid == 36 and guid ~= DC_NULL then
			local okE, ent = pcall(Ext.Entity.GetCharacter, guid)
			local okM, inParty = pcall(Osi.CharacterIsPartyMember, guid)
			if okE and ent ~= nil and okM and inParty == 1 then
				local name = guid
				local okN, handle = pcall(Osi.CharacterGetDisplayName, guid)
				if okN and handle then
					local okT, translated = pcall(Ext.L10N.GetTranslatedString, handle, handle)
					name = (okT and translated) or handle
				end

				local hitDone = SafeStat(stats.HitDone)
				local dmgDone = SafeStat(stats.DamageDone)
				local deaths  = SafeStat(stats.Death)
				local kills   = SafeStat(stats.Kills)

				local copy = {}
				for k, v in pairs(stats) do copy[k] = v end

				local userId, profileId, userName = DC_ProfileOf(guid)

				-- Dettaglio per skill: nome tradotto e icona presi dallo stat
				-- entry. L'icona per ora e' solo un nome logico nel JSON, per
				-- quando estrarremo le texture.
				local skills = {}
				for skillId, s in pairs((PersistentVars.SkillStats or {})[guid] or {}) do
					local skillName, skillIcon = DC_SkillMeta(skillId)
					table.insert(skills, {
						id = skillId,
						name = skillName,
						icon = skillIcon,
						uses = SafeStat(s.Uses),
						hits = SafeStat(s.Hits),
						damage = SafeStat(s.Damage),
						critHits = SafeStat(s.CritHits),
						critDamage = SafeStat(s.CritDamage),
						maxHit = SafeStat(s.MaxHit),
					})
				end
				table.sort(skills, function(a, b) return a.damage > b.damage end)

				table.insert(players, {
					guid = guid,
					name = name,
					userId = userId,
					profileId = profileId,
					userName = userName,
					isHost = (hostGuid ~= nil and guid == hostGuid) or false,
					stats = copy,
					skills = skills,
					derived = {
						-- Calcolati qui e non nella pagina, cosi' il grafico e
						-- il leaderboard in gioco mostrano sempre gli stessi numeri.
						avgDamage = hitDone > 0 and (dmgDone / hitDone) or 0,
						critRate  = hitDone > 0 and (SafeStat(stats.CriticalHits) / hitDone * 100) or 0,
						missRate  = hitDone > 0 and (SafeStat(stats.AttacksMissed) / hitDone * 100) or 0,
						kda       = deaths > 0 and (kills / deaths) or kills,
						summonShare = dmgDone > 0 and (SafeStat(stats.SummonDamageDone) / dmgDone * 100) or 0,
					}
				})
			end
		end
	end
	-- Il profilo "proprietario" della run e' quello dell'HOST: e' sulla sua
	-- macchina che questo codice gira e che i file vengono scritti. Il primo
	-- umano trovato resta solo come ripiego se l'host non e' identificabile
	-- (l'ordine di pairs non e' deterministico, non puo' essere la regola).
	local ownerProfile, ownerName
	for _, pl in ipairs(players) do
		if pl.isHost and pl.profileId then
			ownerProfile, ownerName = pl.profileId, pl.userName
			break
		end
	end
	if ownerProfile == nil then
		for _, pl in ipairs(players) do
			if pl.profileId then
				ownerProfile, ownerName = pl.profileId, pl.userName
				break
			end
		end
	end

	return {
		updatedAt = DC_Now(),
		runId = DC_RunId(),
		profileId = ownerProfile,
		profileName = ownerName,
		hostGuid = hostGuid,
		playerCount = #players,
		players = players,
		-- Ultimi scontri (max DC_MAX_FIGHTS), dal piu' vecchio al piu' recente:
		-- la pagina /fights li mostra al contrario.
		fights = PersistentVars.Fights or {},
	}
end

local function DC_Export(reason)
	local ok, payload = pcall(DC_BuildPayload)
	if not ok then
		Ext.Print("[DamageCounter] export fallito nella raccolta dati: " .. tostring(payload))
		return
	end
	local okJ, json = pcall(Ext.Json.Stringify, payload)
	if not okJ then
		Ext.Print("[DamageCounter] export fallito nella serializzazione: " .. tostring(json))
		return
	end
	local api = DC_WriteFile(DC_EXPORT_FILE, json)
	-- Copia archiviata per profilo e per run, cosi' caricare un altro
	-- salvataggio non cancella i numeri di quello precedente.
	if api ~= nil then
		local prof = payload.profileId or "SenzaProfilo"
		pcall(DC_WriteFile, string.format(DC_RUN_FILE_FMT, prof, payload.runId), json)
	end
	if api == nil then
		Ext.Print("[DamageCounter] nessuna API di scrittura file disponibile " ..
			"(ne' Ext.IO.SaveFile ne' Ext.SaveFile)")
		return
	end
	dcLastExport = DC_Now()
	dcDirty = false
	if reason == "manuale" then
		Ext.Print(string.format("[DamageCounter] scritto %s (%d personaggi) via %s",
			DC_EXPORT_FILE, payload.playerCount, api))
	end
end

-- Chiamata dai punti che modificano le statistiche: segna soltanto, non
-- scrive. La scrittura vera avviene al massimo ogni DC_EXPORT_MIN_INTERVAL,
-- altrimenti si farebbe I/O sul thread di gioco a ogni colpo - che e'
-- esattamente il tipo di problema appena tolto dal percorso caldo.
function DC_MarkDirty()
	dcDirty = true
end

local function DC_TickExport()
	if not dcDirty then return end
	if DC_Now() - dcLastExport < DC_EXPORT_MIN_INTERVAL then return end
	DC_Export("automatico")
end

-- PANNELLO IN-GAME ----------------------------------------
-- Il client (UI/DamageBoardUI.lua) chiede il testo con DC_RequestBoard alla
-- pressione di F7; qui si costruisce dallo stesso payload dell'export web,
-- cosi' pannello e pagina mostrano sempre gli stessi numeri.

local DC_BOARD_ROWS = {
	{ "DamageDone",           "Damage dealt" },
	{ "SummonDamageDone",     "- from summons" },
	{ "AllyDamageDone",       "- on allies (friendly fire)" },
	{ "AllyHitDone",          "Hits on allies" },
	{ "AllyDamageTaken",      "Damage taken from allies" },
	{ "SelfDamage",           "Self-inflicted damage" },
	{ "DamageTaken",          "Damage taken" },
	{ "HealingDone",          "Healing done" },
	{ "HealingReceived",      "Healing received" },
	{ "HighestDamage",        "Biggest hit" },
	{ "HitDone",              "Hits landed" },
	{ "HitTaken",             "Hits taken" },
	{ "CriticalHits",         "Critical hits" },
	{ "CriticalDmgDone",      "Critical damage dealt" },
	{ "CriticalHitsTaken",    "Criticals taken" },
	{ "CriticalDmgTaken",     "Critical damage taken" },
	{ "Kills",                "Kills" },
	{ "Death",                "Deaths" },
	{ "AttacksMissed",        "Attacks missed" },
	{ "MissedAttacks",        "Attacks dodged" },
	{ "AttackBlocked",        "Attacks blocked" },
	{ "BlockedAttack",        "Successful blocks" },
	{ "DamageSkillUsed",      "Damage skills used" },
	{ "DamageSkillDone",      "Skill damage dealt" },
	{ "DamageSkillTaken",     "Skill damage taken" },
	{ "SurfaceDamageDone",    "Surface damage dealt" },
	{ "SurfaceDamageTaken",   "Surface damage taken" },
	{ "SurfaceHitDone",       "Surface hits dealt" },
	{ "SurfaceHitTaken",      "Surface hits taken" },
	{ "StatusDamageDone",     "Status damage dealt" },
	{ "StatusDamageTaken",    "Status damage taken" },
	{ "StatusHitDone",        "Status hits dealt" },
	{ "StatusHitTaken",       "Status hits taken" },
	{ "ReflectedDamage",      "Damage reflected onto attackers" },
	{ "DamageFromReflection", "Damage taken from reflection" },
	{ "SkillUsed",            "Skills used" },
	{ "Resurrected",          "Resurrections" },
	{ "LootedCorpses",        "Corpses looted" },
	{ "DestroyedItem",        "Items destroyed" },
}

local function DC_BoardText()
	local ok, payload = pcall(DC_BuildPayload)
	if not ok or payload == nil or payload.players == nil or #payload.players == 0 then
		return "No stats yet - land a few hits first."
	end
	table.sort(payload.players, function(a, b)
		return (a.stats.DamageDone or 0) > (b.stats.DamageDone or 0)
	end)

	local names = {}
	for _, p in ipairs(payload.players) do table.insert(names, p.name) end
	local lines = { table.concat(names, "  /  "), "" }

	-- Le righe a zero per tutti si saltano: msgBox non scrolla, e con 38 righe
	-- piene il testo uscirebbe dal pannello.
	for _, row in ipairs(DC_BOARD_ROWS) do
		local vals, any = {}, false
		for _, p in ipairs(payload.players) do
			local v = p.stats[row[1]] or 0
			if v ~= 0 then any = true end
			table.insert(vals, formatNumber(v))
		end
		if any then
			table.insert(lines, row[2] .. ":  " .. table.concat(vals, "  /  "))
		end
	end

	table.insert(lines, "")
	local derived = {
		{ "avgDamage",   "Avg damage/hit", "%.0f" },
		{ "critRate",    "Crit rate",      "%.0f%%" },
		{ "missRate",    "Miss rate",      "%.0f%%" },
		{ "kda",         "Kills/deaths",   "%.1f" },
		{ "summonShare", "Summon share",   "%.0f%%" },
	}
	for _, d in ipairs(derived) do
		local vals = {}
		for _, p in ipairs(payload.players) do
			table.insert(vals, string.format(d[3], p.derived[d[1]] or 0))
		end
		table.insert(lines, d[2] .. ":  " .. table.concat(vals, "  /  "))
	end

	return table.concat(lines, "\n")
end

Ext.RegisterNetListener("DC_RequestBoard", function(_, _, user)
	local text = DC_BoardText()
	-- Risposta al solo richiedente quando l'API lo permette; broadcast come
	-- ripiego (in singolo e' la stessa cosa).
	if user ~= nil and type(Ext.Net.PostMessageToUser) == "function" then
		if pcall(Ext.Net.PostMessageToUser, user, "DC_ShowBoard", text) then return end
	end
	pcall(Ext.Net.BroadcastMessage, "DC_ShowBoard", text)
end)

-- REGISTERS ----------------------------------------

Ext.RegisterNetListener("examineContest", function(channel, payload)
	local newtext = ShowConsoleLeaderboard(nil)
	Ext.Net.PostMessageToClient(payload, "PlayerStats", newtext)
end)

-- Elenco di cosa e' stato agganciato davvero, per !dcprobe.
dcListenerStatus = {}

-- Registrazione difensiva. Prima bastava che UNA RegisterListener sollevasse
-- un'eccezione (nome sbagliato, arieta' che non combacia, evento non presente
-- nella story caricata) perche' tutte le successive non venissero mai
-- agganciate - in silenzio. Cosi' ogni fallimento e' isolato e visibile.
local function safeListener(name, arity, when, fn)
	local ok, err = pcall(Ext.Osiris.RegisterListener, name, arity, when, fn)
	dcListenerStatus[name] = ok and "ok" or ("FALLITO: " .. tostring(err))
	if not ok then
		Ext.Print("[DamageCounter] impossibile agganciare " .. name .. ": " .. tostring(err))
	end
	return ok
end

-- CC "duri" vanilla, per id status. Gli status di mod di solito non hanno
-- questi id ma sono COSTRUITI su questi tipi motore: per quelli decide il
-- StatusType dello stat entry (INCAPACITATE copre stun/gelo/pietra/sonno).
local DC_CC_STATUS = {
	KNOCKED_DOWN = true, STUNNED = true, FROZEN = true, PETRIFIED = true,
	CHARMED = true, FEAR = true, TAUNTED = true, SLEEPING = true,
	CHICKEN = true, MADNESS = true,
}
local DC_CC_TYPES = {
	KNOCKED_DOWN = true, INCAPACITATE = true, CHARMED = true,
	FEAR = true, TAUNTED = true, MADNESS = true,
}

-- true se lo status e' un CC, per id vanilla o per tipo motore.
local function DC_IsCCStatus(statusId)
	if DC_CC_STATUS[statusId] then return true end
	local ok, entry = pcall(Ext.Stats.Get, statusId)
	if not ok or entry == nil then return false end
	local okT, st = pcall(function() return entry.StatusType end)
	if not okT or st == nil then return false end
	return DC_CC_TYPES[tostring(st)] == true
end

local function RegisterEventHandlers()

	-- PER-FIGHT: snapshot all'ingresso in combattimento, diff alla fine.
	safeListener("ObjectEnteredCombat", 2, "after", function (object, combatId)
		DC_OnEnteredCombat(object, combatId)
	end)

	safeListener("CombatEnded", 1, "after", function (combatId)
		DC_OnCombatEnded(combatId)
	end)

	-- CC. CharacterStatusApplied scatta solo quando lo status si applica
	-- DAVVERO: i CC respinti dall'armatura non passano di qui.
	safeListener("CharacterStatusApplied", 3, "after", function (character, statusId, causee)
		if not DC_IsCCStatus(tostring(statusId)) then return end
		UpdateStats(causee, { CCInflicted = 1 })
		UpdateStats(character, { CCReceived = 1 })
	end)

	safeListener("CharacterUsedItem", 2, "after", function (charGUID, itemGUID)
		local item = Osi.GetTemplate(itemGUID)
		if item == "LLDT_DestroyerPack_bf47c251-0e5d-456c-bf7d-511cb055bb4e" then
			ShowConsoleLeaderboard(charGUID)
		end
	end)
	
	safeListener("CharacterDestroyedItem", 2, "after", function (_Character, _Item)
		UpdateStats(_Character, { DestroyedItem = 1 })
	end)

	-- La morte va agganciata a CharacterDied, non a CharacterKilledBy:
	-- quest'ultimo scatta solo quando c'e' un uccisore identificabile. Morire
	-- per superficie, veleno, caduta o danno senza attaccante non lo faceva
	-- scattare affatto, e la morte non veniva contata.
	safeListener("CharacterDied", 1, "after", function (character)
		UpdateStats(character, { Death = 1 })
		if DC_HITLOG then
			Ext.Print("[MORTE] " .. tostring(character))
		end
	end)

	-- Listener per l'evento di uccisione
	safeListener("CharacterKilledBy", 3, "after", function (defender, attackerOwner, attacker)
		-- attackerOwner era ignorato. Il motore lo distingue gia' da attacker:
		-- per un'evocazione contiene l'evocatore, quindi l'uccisione finisce
		-- al padrone senza che dobbiamo risalire noi con CharacterGetOwner.
		local killer = NormalizeGuid(attackerOwner) or NormalizeGuid(attacker)
		if killer ~= nil then
			UpdateStats(killer, { Kills = 1 })
		end
	end)

	safeListener("CharacterLootedCharacterCorpse", 2, "after", function (_Character, _Corpse)
		-- Assicurati che la tabella LootedCorpses sia inizializzata
		if PersistentVars.LootedCorpses == nil then
			PersistentVars.LootedCorpses = {}
		end
	
		-- Verifica se il corpse è già stato lotato
		if not PersistentVars.LootedCorpses[_Corpse] then
			-- Se non è stato lotato, aggiorna lo stato e segna come lotato
			PersistentVars.LootedCorpses[_Corpse] = true
			UpdateStats(_Character, { LootedCorpses = 1 })
		end
	end)

	-- DIAGNOSI: evento VANILLA che scatta a ogni colpo fisico (story_header
	-- riga 364). Serve a distinguere due casi molto diversi:
	--   entrambi a 0  -> nessun listener Osiris viene agganciato
	--   questo sale, StatusHitEnter no -> l'evento Lua dell'Extender non
	--                                     viene dispatchato (vedi dcHitEventStatus)
	safeListener("CharacterPhysicalHitBy", 3, "after", function (defender, attackOwner, attacker)
		dcVanillaHits = dcVanillaHits + 1
		if DC_HITLOG then
			Ext.Print(string.format("[VANILLA %d] difensore=%s proprietario=%s attaccante=%s",
				dcVanillaHits, tostring(defender), tostring(attackOwner), tostring(attacker)))
		end
	end)

	-- SkillUsed era dichiarato in InitializeStatTable e raccolto per il
	-- leaderboard, ma nessuno lo incrementava: restava a zero da sempre.
	-- Mancava semplicemente il listener.
	safeListener("CharacterUsedSkill", 4, "after", function (character, skill, skillType, skillElement)
		UpdateStats(character, { SkillUsed = 1 })
		UpdateSkillStats(character, DC_CleanSkillId(skill), { Uses = 1 })
	end)

	-- Era "resurrected" minuscolo, quindi fuori dallo schema di
	-- InitializeStatTable: creava un campo parallelo che non veniva mai letto.
	safeListener("CharacterResurrected", 1, "after", function (_Character)
		UpdateStats(_Character, { Resurrected = 1 })
	end)

	-- Se questa riga non viene raggiunta, uno dei RegisterListener sopra ha
	-- sollevato un'eccezione e i successivi non sono stati agganciati.
	dcHandlersRegistered = true
	Ext.Print("[DamageCounter] listener di sessione registrati")
end


Ext.RegisterConsoleCommand("stats", function()
	-- Prima il valore di ritorno veniva scartato: il comando non stampava nulla.
	local out = ShowConsoleLeaderboard(nil, true)
	if out == nil then
		Ext.Print("[DamageCounter] nessun dato da mostrare")
	else
		Ext.Print(out)
	end
end)

Ext.RegisterConsoleCommand("reset_stats", function()
	ResetStats()
	Ext.Print("[DamageCounter] ATTENZIONE: il danno inflitto mostrato viene da " ..
		"player.DamageCounter, un contatore del motore. Questo reset NON lo azzera.")
end)

Ext.RegisterConsoleCommand("clear_non_player", function()
	clearNonPlayerStats()
end)

Ext.RegisterConsoleCommand("purge_non_player", function()
	purgeNonPlayerStats()
end)

-- Fotografia diagnostica: chi c'e' in tabella e come lo classifica il gioco.
-- Serve a verificare la correzione del filtro (party visibile in singolo) e a
-- confrontare le nostre statistiche con i contatori del motore.
Ext.RegisterConsoleCommand("hitlog", function()
	DC_HITLOG = not DC_HITLOG
	Ext.Print("[DamageCounter] log per colpo: " .. (DC_HITLOG and "ACCESO" or "spento"))
end)

Ext.RegisterConsoleCommand("dcprobe", function()
	Ext.Print("=== SONDA DamageCounter ===")
	Ext.Print(string.format("  StatusHitEnter (Extender) ricevuti: %d   errori: %d   aggancio: %s",
		dcHitsSeen, dcHitsErrored, tostring(dcHitEventStatus)))
	Ext.Print(string.format("  cure HEAL ricevute: %d   aggancio: %s",
		dcHealsSeen or 0, tostring(dcHealEventStatus)))
	Ext.Print(string.format("  CharacterPhysicalHitBy (vanilla) ricevuti: %d", dcVanillaHits))
	local missing = ""
	for name in pairs(dcMissingHitFlags or {}) do missing = missing .. " " .. name end
	if missing ~= "" then
		Ext.Print("  FLAG COLPO NON TROVATI (contati come falsi!):" .. missing)
	end
	if dcReflLog and #dcReflLog > 0 then
		Ext.Print("  ultimi colpi riflessi (piu' recente per primo):")
		for _, line in ipairs(dcReflLog) do
			Ext.Print("    " .. line)
		end
	end
	Ext.Print("  listener di sessione registrati: " ..
		(dcHandlersRegistered and "SI" or "NO  <-- RegisterEventHandlers non e' arrivata in fondo"))
	local any = false
	for name, state in pairs(dcListenerStatus or {}) do
		if state ~= "ok" then
			Ext.Print("    " .. name .. " -> " .. state)
			any = true
		end
	end
	if not any and dcHandlersRegistered then
		Ext.Print("    (tutti agganciati correttamente)")
	end
	local n = 0
	for guid, stats in pairs(PersistentVars.DamageStats or {}) do
		n = n + 1
		-- Sui GUID non validi le query del motore stampano un muro di
		-- "No component found": segnalo la voce e passo oltre.
		if guid == DC_NULL or #guid ~= 36 then
			Ext.Print(string.format(
				"  %s\n     >>> VOCE SPURIA (non e' un personaggio) - togliila con !clear_non_player" ..
				"\n     HighestDamage=%s", tostring(guid), tostring(stats.HighestDamage)))
		else
		local function q(fn, ...)
			local ok, v = pcall(fn, ...)
			if ok and v ~= nil then return tostring(v) end
			return "?"
		end
		local ent = nil
		local okE, e = pcall(Ext.Entity.GetCharacter, guid)
		if okE then ent = e end

		Ext.Print(string.format(
			"  %s\n     nome=%s  party=%s  player=%s  summon=%s  owner=%s\n" ..
			"     MOTORE: DamageCounter=%s HealCounter=%s KillCounter=%s\n" ..
			"     NOSTRE: HitDone=%s DamageTaken=%s CriticalDmgDone=%s HighestDamage=%s",
			tostring(guid),
			q(Osi.CharacterGetDisplayName, guid),
			q(Osi.CharacterIsPartyMember, guid),
			q(Osi.NRD_CharacterGetInt, guid, "IsPlayer"),
			q(Osi.CharacterIsSummon, guid),
			q(Osi.CharacterGetOwner, guid),
			ent and tostring(ent.DamageCounter) or "?",
			ent and tostring(ent.HealCounter) or "?",
			ent and tostring(ent.KillCounter) or "?",
			tostring(stats.HitDone), tostring(stats.DamageTaken),
			tostring(stats.CriticalDmgDone), tostring(stats.HighestDamage)))
		end
	end
	if n == 0 then
		Ext.Print("  (tabella vuota - fai qualche colpo prima)")
	else
		Ext.Print(string.format("=== %d voci ===", n))
	end
end)

Ext.RegisterConsoleCommand("export", function()
	DC_Export("manuale")
end)

-- Export automatico. Ext.Events.Tick non esiste in tutte le versioni
-- dell'Extender: se manca, resta comunque il comando !export a mano.
if Ext.Events and Ext.Events.Tick then
	Ext.Events.Tick:Subscribe(DC_TickExport)
	Ext.Print("[DamageCounter] export automatico attivo (ogni " ..
		(DC_EXPORT_MIN_INTERVAL / 1000) .. "s quando ci sono novita')")
else
	Ext.Print("[DamageCounter] Ext.Events.Tick non disponibile: usa !export a mano")
end

Ext.Events.SessionLoaded:Subscribe(LoadSavedData)
Ext.Events.SessionLoaded:Subscribe(RegisterEventHandlers)
-- La pulizia ora gira una volta al caricamento, non a ogni colpo.
Ext.Events.SessionLoaded:Subscribe(clearNonPlayerStats)
