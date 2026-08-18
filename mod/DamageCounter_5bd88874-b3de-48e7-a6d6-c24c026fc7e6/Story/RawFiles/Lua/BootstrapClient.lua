-- SCOLLEGATO: Ext.Require("UI/DamageLeaderboardUI.lua")
--
-- Il file resta dov'e', in UI/, ma non viene piu' caricato. Era l'unico punto
-- della mod che usasse Epip (Client.UI.Generic per la finestra, le sue texture,
-- l'aggancio a Client.UI.Examine): non caricandolo, la dipendenza da Epip
-- sparisce e la mod gira da sola.
--
-- Il leaderboard ora vive nella pagina web servita da damagecounter_web, che
-- legge il JSON scritto da DC_Export in Osiris Data.
--
-- Per riattivarlo: rimetti il require qui E riaggiungi Epip alle dipendenze in
-- meta.lsx. Senza, Client.UI.Generic non esiste e il file va in errore.
Ext.Require("Shared.lua")
-- Pannello statistiche in-game (F7). Solo API Extender + msgBox vanilla,
-- nessuna dipendenza da Epip o LeaderLib.
Ext.Require("UI/DamageBoardUI.lua")
