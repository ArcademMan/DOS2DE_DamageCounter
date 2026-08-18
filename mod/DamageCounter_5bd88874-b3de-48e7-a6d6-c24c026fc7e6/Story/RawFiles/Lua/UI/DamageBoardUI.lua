-- Pannello statistiche in-game, senza dipendenze: usa una istanza privata di
-- msgBox.swf, la finestra di messaggio VANILLA del gioco, pilotata via Invoke.
-- La sequenza di chiamate Flash (setPopupType/setText/showMsgbox/addButton)
-- viene da LeaderLib, che usa lo stesso pannello per i suoi dialoghi.
--
-- Flusso: F7 -> chiede le statistiche al server (DC_RequestBoard) -> il server
-- risponde con il testo gia' formattato (DC_ShowBoard) -> il pannello si apre.
-- F7 di nuovo, il bottone Close o Escape lo chiudono.

local DC_UI_NAME = "DC_BoardUI"
local DC_UI_LAYER = 15
local DC_TOGGLE_KEY = "f7"   -- InputRawType dell'Extender, minuscolo

-- Margini dentro il pannello, in coordinate del swf: quanto lasciare tra il
-- bordo superiore dello sfondo e il testo, e tra il testo e i bottoni.
local DC_TOP_MARGIN = 90
local DC_BOTTOM_MARGIN = 40

local dcBoardVisible = false
local dcResizeWarned = false
local dcGeomPrinted = false

local function DC_GetUI()
	local ui = Ext.UI.GetByName(DC_UI_NAME)
	if ui == nil then
		ui = Ext.UI.Create(DC_UI_NAME, "Public/Game/GUI/msgBox.swf", DC_UI_LAYER)
		if ui == nil then
			Ext.Print("[DamageCounter] impossibile creare il pannello (msgBox.swf)")
			return nil
		end
		-- id 3 = bottone di chiusura, stessa convenzione dei dialoghi vanilla.
		Ext.RegisterUICall(ui, "ButtonPressed", function(_, _, _id)
			ui:Hide()
			dcBoardVisible = false
		end)
	end
	return ui
end

local function DC_HideBoard()
	local ui = Ext.UI.GetByName(DC_UI_NAME)
	if ui ~= nil then ui:Hide() end
	dcBoardVisible = false
end

-- Percorso preferito: chiamate dirette sul root Flash, che sono SINCRONE.
-- Serve perche' l'ordine conta: INT_SetTextPosition (dentro setText/showMsgbox)
-- centra il blocco di testo sull'altezza del campo, e con un campo alto lo
-- manda meta' sopra la cornice e meta' sotto i bottoni. Qui invece si misura
-- lo spazio reale del pannello (sfondo -> bottoni), si dimensiona il campo su
-- quello, e DOPO il ricalcolo del pannello si rimette il blocco al suo posto.
local function DC_ShowBoardViaRoot(ui, text)
	local root = ui:GetRoot()
	if root == nil then return false end
	return pcall(function()
		root.removeButtons()
		root.addButton(3, "Close", "", "")
		root.setPopupType(1)
		local p = root.popup_mc
		local txt = p.text_mc.text_txt
		local top = p.bg_mc.y + DC_TOP_MARGIN
		local h = p.cButtons_mc.y - DC_BOTTOM_MARGIN - top
		if h < 150 then h = 150 end
		if not dcGeomPrinted then
			dcGeomPrinted = true
			Ext.Print(string.format(
				"[DamageCounter] pannello: sfondo y=%.0f h=%.0f  bottoni y=%.0f  -> testo y=%.0f h=%.0f",
				p.bg_mc.y, p.bg_mc.height, p.cButtons_mc.y, top, h))
		end
		txt.height = h
		root.setText(text)
		root.showMsgbox()
		p.text_mc.y = top
	end)
end

local function DC_ShowBoard(text)
	local ui = DC_GetUI()
	if ui == nil then return end
	local okR, err = DC_ShowBoardViaRoot(ui, text)
	if not okR then
		-- Ripiego: sequenza via Invoke, senza ridimensionare (altezza vanilla,
		-- si scorre con la rotella). Avvisa: niente ripieghi silenziosi.
		if not dcResizeWarned then
			dcResizeWarned = true
			Ext.Print("[DamageCounter] pannello: ridimensionamento fallito (" ..
				tostring(err) .. "); uso il layout vanilla con scroll.")
		end
		ui:Invoke("removeButtons")
		ui:Invoke("addButton", 3, "Close", "", "")
		ui:Invoke("setPopupType", 1)
		ui:Invoke("setText", text)
		ui:Invoke("showMsgbox")
	end
	ui:Show()
	dcBoardVisible = true
end

Ext.RegisterNetListener("DC_ShowBoard", function(_, payload)
	DC_ShowBoard(payload)
end)

-- Escape chiude il pannello come qualsiasi finestra di gioco.
Ext.Events.RawInput:Subscribe(function(e)
	local input = e.Input
	if input == nil or input.Input == nil or input.Value == nil then return end
	local key = tostring(input.Input.InputId)
	local pressed = tostring(input.Value.State) == "Pressed"
	if not pressed then return end

	if key == "escape" then
		if dcBoardVisible then DC_HideBoard() end
		return
	end
	if key ~= DC_TOGGLE_KEY then return end

	-- Fuori dalla partita (menu, caricamenti) il tasto non deve fare nulla.
	local okG, state = pcall(Ext.Client.GetGameState)
	if not okG or tostring(state) ~= "Running" then return end

	if dcBoardVisible then
		DC_HideBoard()
	else
		Ext.Net.PostMessageToServer("DC_RequestBoard", "")
	end
end)
