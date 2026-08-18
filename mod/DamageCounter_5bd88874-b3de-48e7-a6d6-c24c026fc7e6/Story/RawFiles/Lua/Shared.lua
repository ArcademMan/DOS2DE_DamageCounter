

-- RIMOSSO: Mods.LeaderLib.Import(Mods.DamageCounter)
--
-- Questa riga agganciava i nostri PersistentVars al sistema di persistenza di
-- LeaderLib, che li scrive e li rilegge da Osiris Data\LeaderLib_Debug_
-- PersistentVars.json - un file globale all'installazione, non legato al
-- salvataggio. Effetto: iniziando una partita nuova si ritrovavano in tabella
-- le statistiche di quella precedente (Lohse con 464 colpi gia' fatti, perche'
-- i personaggi origine hanno GUID fissi tra le partite).
--
-- Lo Script Extender salva gia' PersistentVars dentro al savegame per ogni mod
-- registrata in ModTable (vedi OsiToolsConfig.json), quindi non serve altro.

Ext.Events.SessionLoaded:Subscribe(function(e)
	--Ext.Utils.Print(string.format("[%s] SessionLoaded running. [%s]", Ext.Mod.GetModInfo(ModuleUUID).Name, Ext.IsClient() and "CLIENT" or "SERVER"))

	local mods = {}

	for i,v in ipairs(Ext.Mod.GetLoadOrder()) do
		local info = Ext.Mod.GetModInfo(v)
		if info then
			table.insert(mods, {
				Index = i,
				UUID = v,
				Name = info.Name
			})
		end
	end

	Ext.Utils.Print("Loaded mods:")
	Ext.Dump(mods)
end)