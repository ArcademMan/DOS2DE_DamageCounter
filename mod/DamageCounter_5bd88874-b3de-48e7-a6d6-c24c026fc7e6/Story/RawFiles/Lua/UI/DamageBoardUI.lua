-- Pannello statistiche in-game (F7).
--
-- Il pannello e' una COPIA PRIVATA di una finestra vanilla, inclusa nel pak
-- della mod: Public/DamageCounter_<uuid>/GUI/DC_Board_Journal.swf. E' una
-- copia NOSTRA, non il file del gioco: cosi' nessun'altra mod la trova con
-- GetByPath e nessun path override altrui (LeaderLib sostituisce journal.swf)
-- ci cambia il pannello sotto i piedi.
--
-- Le pagine diventano voci cliccabili nella lista di sinistra e il testo
-- appare a destra, dove scorre. Il riempimento usa lo stesso meccanismo con
-- cui LeaderLib scrive il suo changelog nel diario: l'array add_tutEntry a
-- gruppi di quattro campi (gruppo, id, titolo, testo), seguito da
-- updateTutorials().
--
-- Comandi: F7 apre e chiude, Esc chiude, il bottone X del pannello chiude,
-- rotella e PagSu/PagGiu'/frecce scorrono, Home torna in cima. Le voci del
-- gruppo Options agiscono invece di mostrare testo (vedi DC_PollSelection).
--
-- Il log di combattimento e la finestrella msgBox erano due contenitori
-- alternativi ciclabili con F6: tolti, insieme al tasto, una volta scelto il
-- diario.
--
-- La scheda Diario (vista quest) e' stata provata e abbandonata: le voci si
-- creano, ma il testo di destra lo mette addQuestAction, la cui firma non e'
-- documentata e che non ha risposto a nessuna delle forme provate. Al click
-- il filmato non chiede nulla al motore (manda solo un suono), quindi non
-- esiste un aggancio da cui passare per riempirla.
--
-- I dati arrivano dal server gia' formattati (canale DC_ShowBoard2): qui si
-- decide solo la disposizione, non il contenuto.
--
-- Diagnostica: ogni riga di log finisce anche in
-- Documents\Larian Studios\...\Osiris Data\DamageCounter_UI.log, perche' le
-- Print del client non compaiono nel log Osiris e la console si perde.

local DC_GUI_DIR = "Public/DamageCounter_5bd88874-b3de-48e7-a6d6-c24c026fc7e6/GUI/"
local DC_LAYER = 15

local DC_TOGGLE_KEY = "f7"

-- Dimensione della finestra, in pixel di Flash (coordinate del filmato).
local DC_W, DC_H = 900, 620

local dcVisible = false
-- Richiesta di chiusura arrivata dal pannello stesso (bottone X). Non si
-- chiude sul momento: il filmato sta ancora gestendo il proprio click, quindi
-- si segna la richiesta e la si esegue al tick successivo.
local dcCloseRequest = false
local dcPages = nil       -- ultimo payload ricevuto
local dcWarned = {}
local dcLogLines = {}
-- Mappa delle voci del diario: nome gruppo -> elenco degli id nell'ordine in
-- cui sono state inserite. Serve a risalire dall'indice della selezione
-- all'id della voce, per riconoscere le voci-comando.
local dcEntryIds = {}
local dcLastCommand = nil
local dcSelProbed = nil

local function DC_Log(msg)
	local line = "[DamageCounter] " .. tostring(msg)
	Ext.Utils.Print(line)
	table.insert(dcLogLines, line)
	-- Il file si riscrive intero ogni volta: poche righe, e cosi' non serve
	-- gestire l'append (che l'API non offre).
	while #dcLogLines > 200 do table.remove(dcLogLines, 1) end
	pcall(Ext.IO.SaveFile, "DamageCounter_UI.log", table.concat(dcLogLines, "\n"))
end

local function DC_WarnOnce(key, msg)
	if dcWarned[key] then return end
	dcWarned[key] = true
	DC_Log(msg)
end

-- Ascolto di TUTTO cio' che i nostri pannelli mandano fuori.
--
-- Quando si clicca una voce, il filmato avvisa il motore con una chiamata
-- ExternalInterface: e' cosi' che nel gioco vero il testo compare a destra.
-- Non sapendo come si chiama quella chiamata, la si intercetta in blocco e la
-- si scrive nel log con i suoi argomenti: e' l'unico modo di sapere cosa
-- aspetta il pannello da noi. Poche righe, poi si tace da solo.
local dcCallsLogged = 0

pcall(function()
	Ext.Events.UICall:Subscribe(function(e)
		local path = ""
		pcall(function() path = tostring(e.UI.Path) end)
		-- Solo le nostre copie: il gioco ne manda a centinaia.
		if string.find(path, "DamageCounter", 1, true) == nil then return end
		local args = {}
		pcall(function()
			for _, a in ipairs(e.Args or {}) do
				table.insert(args, tostring(a))
			end
		end)
		-- Il bottone X non chiude nulla da solo: nel gioco e' il motore a
		-- farlo. L'unico segno che manda e' il suono del click, quindi si usa
		-- quello come richiesta di chiusura.
		if tostring(e.Function) == "PlaySound" and args[1] ~= nil
			and string.find(args[1], "XButton", 1, true) ~= nil then
			dcCloseRequest = true
		end

		if dcCallsLogged < 40 then
			dcCallsLogged = dcCallsLogged + 1
			DC_Log("UICall " .. tostring(e.Function) .. "(" ..
				table.concat(args, ", ") .. ")")
		end
	end)
end)

-- ---------------------------------------------------------------------------
-- Formattazione
--
-- Il testo dei pannelli Flash accetta solo un HTML minimo: <b>, <i>, <font>,
-- <br>, <textformat tabstops>. Le colonne si allineano con i tabstop, non con
-- gli spazi: il font non e' a spaziatura fissa.

-- Un tema per contenitore: gli stessi colori non possono servire a entrambi.
-- Il log e' una finestra scura e vuole testo chiaro; il diario e' una pagina
-- di pergamena e vuole testo scuro, grande e con margini larghi, come il
-- diario vero. Tenerne uno solo era la ragione per cui la nostra pagina si
-- leggeva peggio di quella di Larian.
--
--   text/title/section/header  colori del testo
--   size                       scostamento dal corpo del font, formato Flash
--   marginL/marginR/leading    aria attorno al testo, in pixel
--   first/step                 dove cade la prima colonna e quanto distano
local DC_THEMES = {
	-- Misure tarate sulla larghezza reale del campo del diario: 450 pixel,
	-- letta in gioco. Con margini da 56 e corpo +3 non ci stavano tre colonne
	-- di numeri, ed e' per questo che ogni valore finiva a capo.
	-- Testo quasi nero: il marrone che avevo scelto veniva reso troppo chiaro
	-- sulla pergamena, mentre il diario vero usa un inchiostro molto scuro.
	journal = {
		text = "#14100A", title = "#7A1F1C", section = "#4A3418",
		header = "#5A4526", size = "+2",
		marginL = 12, marginR = 12, leading = 5,
		first = 210, step = 100,
	},
}

-- Nomi lunghi nell'intestazione: se superano la distanza tra due tabstop, la
-- colonna successiva finisce a capo e l'intestazione si sfalsa (e' quello che
-- succedeva con "Higba il Riparatore").
local function DC_Trunc(s, n)
	s = tostring(s or "")
	if #s <= n then return s end
	return string.sub(s, 1, n - 1) .. "."
end

local function DC_EscapeHtml(s)
	s = tostring(s or "")
	s = string.gsub(s, "&", "&amp;")
	s = string.gsub(s, "<", "&lt;")
	s = string.gsub(s, ">", "&gt;")
	return s
end

local function DC_TabStops(n, first, step)
	local stops = {}
	local count = n
	if count < 1 then count = 1 end
	for i = 1, count do
		table.insert(stops, tostring(first + (i - 1) * step))
	end
	return "[" .. table.concat(stops, ",") .. "]"
end

-- Ogni riga porta con se' margini, interlinea e tabstop: sono attributi di
-- paragrafo, e nel markup Flash non esiste un contenitore che li erediti.
local function DC_Wrap(theme, inner, tabstops)
	local attrs = string.format(
		"leftmargin='%d' rightmargin='%d' leading='%d'",
		theme.marginL, theme.marginR, theme.leading)
	if tabstops ~= nil then
		attrs = attrs .. " tabstops='" .. tabstops .. "'"
	end
	return "<textformat " .. attrs .. ">" .. inner .. "</textformat>"
end

local function DC_Font(theme, color, inner, bold)
	local s = "<font color='" .. color .. "' size='" .. theme.size .. "'>" ..
		inner .. "</font>"
	if bold then s = "<b>" .. s .. "</b>" end
	return s
end

local function DC_Row(theme, label, values, color, bold)
	local vals = values or {}
	local parts = { DC_EscapeHtml(label) }
	for _, v in ipairs(vals) do
		table.insert(parts, DC_EscapeHtml(v))
	end
	local line = DC_Font(theme, color or theme.text, table.concat(parts, "\t"), bold)
	return DC_Wrap(theme, line, DC_TabStops(#vals, theme.first, theme.step))
end

-- Quante colonne di valori ha, al massimo, una pagina.
local function DC_PageColumns(page)
	local n = 0
	for _, sec in ipairs(page.sections or {}) do
		local h = #(sec.header or {}) - 1
		if h > n then n = h end
		for _, row in ipairs(sec.rows or {}) do
			local c = #(row.values or {})
			if c > n then n = c end
		end
	end
	if n < 1 then n = 1 end
	return n
end

-- Colonne calcolate sulla larghezza VERA del campo di testo, non a occhio.
-- I tabstop sono assoluti dal bordo sinistro del campo e i margini non li
-- spostano: se cadono oltre la larghezza utile, ogni valore va a capo ed e'
-- esattamente il pasticcio che si vedeva nella pagina del diario.
local function DC_FitTheme(base, width, columns)
	if width == nil or width <= 0 then return base end
	local theme = {}
	for k, v in pairs(base) do theme[k] = v end

	local usable = width - base.marginL - base.marginR
	if usable < 200 then
		-- Campo stretto: si rinuncia ai margini larghi pur di far stare i numeri.
		theme.marginL = 12
		theme.marginR = 12
		usable = width - 24
	end
	-- Poco meno di meta' larghezza all'etichetta, il resto diviso tra i valori.
	local labelWidth = math.floor(usable * 0.46)
	local step = math.floor((usable - labelWidth) / columns)
	if step < 60 then step = 60 end
	theme.first = theme.marginL + labelWidth
	theme.step = step
	return theme
end

-- Una pagina intera come testo HTML, nei colori e nelle misure del tema.
local function DC_PageHtml(page, withTitle, theme)
	theme = theme or DC_THEMES.journal
	local out = {}
	if withTitle then
		table.insert(out, DC_Wrap(theme,
			DC_Font(theme, theme.title, DC_EscapeHtml(page.title), true)))
		table.insert(out, "")
	end
	for _, sec in ipairs(page.sections or {}) do
		if sec.title ~= nil and sec.title ~= "" then
			table.insert(out, DC_Wrap(theme,
				DC_Font(theme, theme.section, DC_EscapeHtml(sec.title), true)))
		end
		local header = sec.header or {}
		if #header > 1 then
			local cols = {}
			-- L'intestazione sta in una colonna sola: si tronca sulla larghezza
			-- disponibile, circa un carattere ogni 8 pixel di tabstop.
			local maxChars = math.floor(theme.step / 8)
			for i = 2, #header do table.insert(cols, DC_Trunc(header[i], maxChars)) end
			table.insert(out, DC_Row(theme, header[1] or "", cols, theme.header, true))
		end
		for _, row in ipairs(sec.rows or {}) do
			table.insert(out, DC_Row(theme, row.label, row.values))
		end
		table.insert(out, "")
	end
	return table.concat(out, "<br>")
end

-- La pagina del diario SCORRE: il campo desc_txt ha uno scorrimento interno
-- (misurato in gioco: maxScrollV 5 con testo alto 702px in una finestra da
-- 600). Quindi le pagine restano intere e non serve piu' spezzarle in
-- "Party (2)", "Party (3)". Il limite resta solo come rete di sicurezza per
-- una pagina mostruosa, molto oltre qualunque contenuto reale.
local DC_JOURNAL_MAX_ROWS = 150

local function DC_SplitPage(page, maxRows)
	local chunks = {}
	local cur = { title = page.title, id = page.id, group = page.group, sections = {} }
	local used = 0

	local function flush()
		if #cur.sections > 0 then
			table.insert(chunks, cur)
		end
		-- Il pezzo che sto aprendo e' il (#chunks + 1)-esimo: "Party (2)" dopo
		-- "Party", "Party (3)" dopo quello, e cosi' via.
		local n = #chunks + 1
		cur = {
			title = tostring(page.title) .. " (" .. tostring(n) .. ")",
			id = tostring(page.id) .. "_" .. tostring(n),
			group = page.group,
			sections = {},
		}
		used = 0
	end

	for _, sec in ipairs(page.sections or {}) do
		local rows = sec.rows or {}
		local i = 1
		local firstPart = true
		while true do
			-- Titolo e intestazione costano due righe per ogni pezzo.
			local room = maxRows - used - 2
			if room < 4 then
				flush()
				room = maxRows - 2
			end
			local part = {}
			while i <= #rows and #part < room do
				table.insert(part, rows[i])
				i = i + 1
			end
			local title = sec.title
			if not firstPart and title ~= nil and title ~= "" then
				title = tostring(title) .. " (cont.)"
			end
			table.insert(cur.sections, {
				title = title, header = sec.header, rows = part,
			})
			used = used + #part + 2
			firstPart = false
			if i > #rows then break end
		end
	end
	if #cur.sections > 0 then table.insert(chunks, cur) end
	if #chunks == 0 then table.insert(chunks, page) end
	return chunks
end

-- Testo semplice, senza markup: serve al ripiego msgBox.
local function DC_PagePlain(page, withTitle)
	local out = {}
	if withTitle then
		table.insert(out, "=== " .. tostring(page.title) .. " ===")
	end
	for _, sec in ipairs(page.sections or {}) do
		if sec.title ~= nil and sec.title ~= "" then
			table.insert(out, tostring(sec.title))
		end
		local header = sec.header or {}
		if #header > 1 then
			local cols = {}
			for i = 2, #header do table.insert(cols, header[i]) end
			table.insert(out, tostring(header[1] or "") .. "  " .. table.concat(cols, "  "))
		end
		for _, row in ipairs(sec.rows or {}) do
			table.insert(out, tostring(row.label) .. ":  " ..
				table.concat(row.values or {}, "  /  "))
		end
		table.insert(out, "")
	end
	return table.concat(out, "\n")
end

-- ---------------------------------------------------------------------------
-- Utilita' comuni ai contenitori

-- Il filmato Flash non e' pronto nell'istante in cui lo si crea: il primo
-- GetRoot() dopo Ext.UI.Create puo' tornare nil. Invece di lasciare un
-- pannello vuoto si ritenta al tick successivo, una volta sola per apertura.
local dcRetryHandle = nil
local dcRetryPending = false

local function DC_ScheduleRetry(fn)
	if dcRetryPending then return end
	dcRetryPending = true
	local ok = pcall(function()
		dcRetryHandle = Ext.Events.Tick:Subscribe(function()
			if dcRetryHandle ~= nil then
				pcall(Ext.Events.Tick.Unsubscribe, Ext.Events.Tick, dcRetryHandle)
				dcRetryHandle = nil
			end
			dcRetryPending = false
			pcall(fn)
		end)
	end)
	if not ok then
		dcRetryPending = false
	end
end

-- Il diario e' un pannello a schermo intero: lo dice lui stesso, chiedendo
-- "registerAnchorId(journal)" e "setAnchor(center, screen, center)". Nel gioco
-- e' il motore a rispondere ancorandolo allo schermo; noi invece lo stavamo
-- rimpicciolendo e centrando a mano, e le aree sensibili restavano dov'erano
-- previste: ecco perche' si poteva cliccare solo in una striscia stretta.
-- Qui si fa quello che farebbe il motore: origine a zero, dimensione dello
-- schermo, e poi il ricalcolo del layout.
-- Il filmato ha una sua dimensione nativa e va centrato su QUELLA: con
-- Resize alla risoluzione dello schermo finiva incollato in alto a sinistra,
-- perche' ridimensionare il filmato non e' la stessa cosa che ancorarlo.
local function DC_FullScreen(ui, root)
	local okV, vp = pcall(Ext.UI.GetViewportSize)
	if not okV or vp == nil then return end
	local vw = vp[1] or vp.x
	local vh = vp[2] or vp.y
	if vw == nil or vh == nil then return end

	-- Dimensione vera del pannello, chiesta al filmato stesso.
	local w, h = nil, nil
	pcall(function() w = root.getWidth() end)
	pcall(function() h = root.getHeight() end)
	if w == nil or w <= 0 then w = DC_W end
	if h == nil or h <= 0 then h = DC_H end

	pcall(function()
		ui:SetPosition(math.floor((vw - w) / 2), math.floor((vh - h) / 2))
	end)
	pcall(function() root.onEventResize() end)
	DC_WarnOnce("fullscreen", string.format(
		"pannello: filmato %sx%s centrato su schermo %sx%s",
		tostring(w), tostring(h), tostring(vw), tostring(vh)))
end

local function DC_Center(ui, w, h)
	local okV, vp = pcall(Ext.UI.GetViewportSize)
	if not okV or vp == nil then return end
	local vw = vp[1] or vp.x
	local vh = vp[2] or vp.y
	if vw == nil or vh == nil then return end
	pcall(function()
		ui:SetPosition(math.floor((vw - w) / 2), math.floor((vh - h) / 2))
	end)
end

-- ---------------------------------------------------------------------------
-- Contenitore 2: copia del diario
--
-- Le voci si aggiungono riempiendo l'array add_tutEntry a gruppi di QUATTRO
-- campi consecutivi (nome del gruppo, id della voce, titolo, testo) e poi
-- chiamando updateTutorials(): e' il modo in cui il diario costruisce la sua
-- scheda dei tutorial, ed e' quello che usa LeaderLib per infilarci il proprio
-- changelog. Le voci finiscono nella lista di sinistra e il testo compare a
-- destra quando si clicca: e' cosi' che gli scontri si aprono uno per uno.

local DC_JOURNAL_UI = "DC_BoardJournal"

-- Scorrimento della pagina di destra.
--
-- Il diario non espone un comando di scroll sul root: il testo vive dentro
-- tutorialContainer_mc, che a seconda di come e' montato puo' essere una lista
-- Larian (scrollUp/scrollDown/scrollTo) oppure un semplice campo di testo, che
-- in Flash si scorre con la proprieta' scrollV. Si provano le strade in
-- ordine e si tiene la prima che risponde, annotandola nel log.
local dcScrollWay = nil

local function DC_JournalContainer(root)
	local c = nil
	pcall(function() c = root.journal_mc.tutorialContainer_mc end)
	return c
end

-- Altezza di riga usata per lo scorrimento manuale, in pixel di Flash.
local DC_LINE_H = 22
local dcDescBaseY = nil
local dcScrollLogged = false

-- Sonda: prova un elenco di nomi su un oggetto Flash e riporta quelli che
-- esistono. Da Lua non si possono elencare le proprieta' di un oggetto Iggy,
-- quindi l'unico modo di sapere com'e' fatto un pannello vanilla e' chiedere
-- un nome alla volta.
local DC_PROBE_NAMES = {
	"journalList", "questList", "questContainer_mc", "journalContainer_mc",
	"addQuestAction", "addSubQuest", "setQuestText", "positionElements",
	"container_mc", "listContainer_mc", "infoContainer_mc", "content_mc",
	"text_mc", "mask_mc", "list", "m_scrollbar_mc", "scrollbar_mc",
	"scrollbar", "scrollbarVisible", "checkScrollBar", "scrollTo",
	"scrollToPercent", "scrollToFit", "scrollUp", "scrollDown", "updateScroll",
	"resetScroll", "resetText", "m_scrolledY", "scrolledY", "m_ScrollHeight",
	"scrollRect", "desc_txt", "text_txt", "title_txt", "height", "y",
	"lastGroupId",
}

local function DC_Probe(obj, label)
	if obj == nil then return label .. "=nil" end
	local found = {}
	for _, name in ipairs(DC_PROBE_NAMES) do
		local ok, v = pcall(function() return obj[name] end)
		if ok and v ~= nil then
			local t = type(v)
			if t == "number" or t == "boolean" or t == "string" then
				table.insert(found, name .. "=" .. tostring(v))
			else
				table.insert(found, name)
			end
		end
	end
	if #found == 0 then return label .. ": niente" end
	return label .. ": " .. table.concat(found, ", ")
end

local function DC_JournalScroll(delta)
	local ui = Ext.UI.GetByName(DC_JOURNAL_UI)
	if ui == nil then return end
	local root = ui:GetRoot()
	if root == nil then return end
	local c = DC_JournalContainer(root)
	if c == nil then return end

	local f = nil
	pcall(function() f = c.desc_txt end)
	if f == nil then
		pcall(function() f = c.text_txt end)
	end
	if f == nil then
		DC_WarnOnce("scroll", "pannello 'journal': nessun campo di testo da scorrere")
		return
	end

	-- Misura vera, presa mentre una voce e' aperta: dice se il campo ha un
	-- eccedenza da scorrere (maxScrollV > 1) o se cresce oltre la cornice
	-- (textHeight > height), che sono due situazioni diverse.
	local maxScroll, textH, boxH, y = 1, 0, 0, 0
	pcall(function() maxScroll = f.maxScrollV or 1 end)
	pcall(function() textH = f.textHeight or 0 end)
	pcall(function() boxH = f.height or 0 end)
	pcall(function() y = f.y or 0 end)
	if not dcScrollLogged then
		dcScrollLogged = true
		DC_Log(string.format(
			"pannello 'journal': campo testo maxScrollV=%s textHeight=%s height=%s y=%s",
			tostring(maxScroll), tostring(textH), tostring(boxH), tostring(y)))
		-- Con una voce aperta si fotografa com'e' fatto il contenitore: e' il
		-- momento buono, perche' il pannello e' popolato.
		DC_Log(DC_Probe(c, "tutorialContainer_mc"))
		local parent = nil
		pcall(function() parent = f.parent end)
		DC_Log(DC_Probe(parent, "parent di desc_txt"))
		local jm = nil
		pcall(function() jm = root.journal_mc end)
		DC_Log(DC_Probe(jm, "journal_mc"))
	end

	-- Se il contenitore espone uno scorrimento suo, e' la via giusta: e' quella
	-- che muovono le frecce del diario vero.
	for _, name in ipairs({ "scrollDown", "scrollUp", "scrollTo", "scrollToPercent" }) do
		local has = false
		pcall(function() has = (c[name] ~= nil) end)
		if has then
			local moved = pcall(function()
				if name == "scrollDown" and delta > 0 then
					for _ = 1, delta do c.scrollDown() end
				elseif name == "scrollUp" and delta < 0 then
					for _ = 1, -delta do c.scrollUp() end
				elseif name == "scrollTo" then
					c.scrollTo((c.m_scrolledY or 0) + delta * DC_LINE_H)
				elseif name == "scrollToPercent" then
					error("non usabile senza percentuale nota")
				else
					error("direzione non gestita")
				end
			end)
			if moved then
				if dcScrollWay ~= name then
					dcScrollWay = name
					DC_Log("pannello 'journal': scorrimento via " .. name)
				end
				return
			end
		end
	end

	-- Strada 1: lo scorrimento interno di Flash, quando c'e' davvero.
	if maxScroll ~= nil and maxScroll > 1 then
		local moved = pcall(function()
			local v = f.scrollV + delta
			if v < 1 then v = 1 end
			if v > maxScroll then v = maxScroll end
			f.scrollV = v
		end)
		if moved then
			if dcScrollWay ~= "scrollV" then
				dcScrollWay = "scrollV"
				DC_Log("pannello 'journal': scorrimento via scrollV")
			end
			return
		end
	end

	-- Strada 2: il campo non scorre perche' cresce in altezza e viene tagliato
	-- dalla cornice. Allora lo si sposta a mano, entro i limiti del testo.
	if dcDescBaseY == nil then dcDescBaseY = y end
	local overflow = textH - boxH
	if overflow < 0 then overflow = 0 end
	local moved = pcall(function()
		local newY = y - (delta * DC_LINE_H)
		if newY > dcDescBaseY then newY = dcDescBaseY end
		if newY < dcDescBaseY - overflow then newY = dcDescBaseY - overflow end
		f.y = newY
	end)
	if moved then
		if dcScrollWay ~= "moveY" then
			dcScrollWay = "moveY"
			DC_Log("pannello 'journal': scorrimento spostando il campo (overflow " ..
				tostring(overflow) .. "px)")
		end
		return
	end

	DC_WarnOnce("scroll", "pannello 'journal': nessuna via di scorrimento disponibile")
end

local DC_JournalShow

function DC_JournalShow(data)
	local ui = Ext.UI.GetByName(DC_JOURNAL_UI)
	if ui == nil then
		ui = Ext.UI.Create(DC_JOURNAL_UI, DC_GUI_DIR .. "DC_Board_Journal.swf", DC_LAYER)
		if ui == nil then
			DC_Log("pannello 'journal': creazione fallita")
			return false
		end
	end

	local root = ui:GetRoot()
	if root == nil then
		DC_ScheduleRetry(function() DC_JournalShow(data) end)
		return true
	end

	local notes = {}
	local function try(name, fn)
		local ok, err = pcall(fn)
		if ok then
			table.insert(notes, name .. "=ok")
		else
			table.insert(notes, name .. "=KO(" .. tostring(err) .. ")")
		end
		return ok
	end

	try("onEventInit", function() root.onEventInit() end)

	-- Il diario non ha clearTutorials: le voci gia' presenti si tolgono
	-- svuotando i gruppi della lista, come fa LeaderLib. Senza questo, ogni
	-- F7 aggiungerebbe una copia di tutte le voci.
	try("clearGroups", function()
		local list = root.journal_mc.tutorialList
		local groups = list.content_array
		for i = #groups - 1, 0, -1 do
			local g = groups[i]
			if g ~= nil and g.groupId ~= nil then
				list.clearGroup(g.groupId, false)
			end
		end
	end)

	-- Riempimento dell'array: quattro campi per voce, indici da 0 in avanti.
	-- Le pagine troppo lunghe si spezzano in piu' voci, perche' la pagina del
	-- diario non scorre e il testo in eccesso resterebbe invisibile.
	-- Il campo di testo nasce largo 450 dentro una pagina molto piu' larga, e
	-- lascia quelle due bande vuote ai lati. Lo si allarga fino quasi al bordo
	-- della pagina: e' una proprieta' del campo, si puo' cambiare da qui.
	local cont = nil
	pcall(function() cont = root.journal_mc.tutorialContainer_mc end)
	local fieldW = nil
	if cont ~= nil then
		-- Il "contenitore" e' largo 1239: sono DUE pagine, non una. Allargare
		-- il campo su quella misura lo spalmava anche sulla pagina sinistra.
		-- Il righello giusto e' il titolo, che il diario centra sulla pagina
		-- destra: la sua fascia e' esattamente lo spazio scrivibile.
		local tx, tw = nil, nil
		pcall(function() tx = cont.title_txt.x end)
		pcall(function() tw = cont.title_txt.width end)
		pcall(function()
			local f = cont.desc_txt
			DC_WarnOnce("fieldbefore", string.format(
				"pannello 'journal': campo x=%s w=%s | titolo x=%s w=%s",
				tostring(f.x), tostring(f.width), tostring(tx), tostring(tw)))
			if tx ~= nil and tw ~= nil and tw > 200 then
				f.x = tx
				f.width = tw
			end
			f.wordWrap = true
			f.multiline = true
			f.alpha = 1
			fieldW = f.width
		end)
	end
	if fieldW == nil then fieldW = 450 end
	DC_Log("pannello 'journal': larghezza campo testo = " .. tostring(fieldW))

	local filled = 0
	dcEntryIds = {}
	try("add_tutEntry", function()
		local arr = root.add_tutEntry
		local idx = #arr
		for _, page in ipairs(data.pages or {}) do
			for _, part in ipairs(DC_SplitPage(page, DC_JOURNAL_MAX_ROWS)) do
				local theme = DC_FitTheme(DC_THEMES.journal, fieldW, DC_PageColumns(part))
				local group = tostring(part.group or "Stats")
				local id = tostring(part.id or part.title)
				arr[idx] = group
				arr[idx + 1] = id
				arr[idx + 2] = tostring(part.title)
				arr[idx + 3] = DC_PageHtml(part, false, theme)
				idx = idx + 4
				filled = filled + 1
				-- Si tiene l'ordine delle voci per gruppo: e' la chiave per
				-- risalire dall'indice della selezione all'id della voce. La
				-- chiave e' in MAIUSCOLO perche' il diario mostra e conserva i
				-- nomi dei gruppi cosi': cercare "Options" dove la lista ha
				-- "OPTIONS" faceva fallire ogni corrispondenza.
				local key = string.upper(group)
				if dcEntryIds[key] == nil then dcEntryIds[key] = {} end
				table.insert(dcEntryIds[key], id)
			end
		end
	end)
	try("updateTutorials", function() root.updateTutorials() end)
	try("showWin", function() root.showWin() end)

	-- Se una sessione precedente aveva spostato il campo di testo per
	-- scorrerlo, si riparte dall'inizio.
	if dcDescBaseY ~= nil then
		pcall(function() DC_JournalContainer(root).desc_txt.y = dcDescBaseY end)
	end

	-- Rotella del mouse sulla pagina di destra: se il contenitore la supporta,
	-- e' il modo piu' naturale di scorrere e non costa nulla provarci.
	try("mouseWheel", function()
		local c = DC_JournalContainer(root)
		c.mouseWheelEnabled = true
		-- Il testo scorre da solo (scrollV): con la rotella abilitata sul campo,
		-- Flash lo scorre senza passare da noi.
		pcall(function() c.desc_txt.mouseWheelEnabled = true end)
		pcall(function() c.setScrollWheelEnabled(true) end)
	end)

	-- Diagnostica: quante voci sono davvero finite nella lista del diario, e
	-- quali agganci di scorrimento esistono sul contenitore del testo.
	local listed = "?"
	pcall(function()
		listed = tostring(#root.journal_mc.tutorialList.content_array)
	end)
	local probe = {}
	local c = DC_JournalContainer(root)
	if c == nil then
		table.insert(probe, "container=nil")
	else
		local checks = {
			{ "scrollUp", function() return c.scrollUp end },
			{ "scrollTo", function() return c.scrollTo end },
			{ "list", function() return c.list end },
			{ "text_txt", function() return c.text_txt end },
			{ "text_txt.maxScrollV", function() return c.text_txt.maxScrollV end },
			{ "desc_txt", function() return c.desc_txt end },
			{ "desc_txt.maxScrollV", function() return c.desc_txt.maxScrollV end },
		}
		for _, chk in ipairs(checks) do
			local okC, v = pcall(chk[2])
			if okC and v ~= nil then
				table.insert(probe, chk[1] .. "=" .. tostring(v))
			end
		end
	end
	DC_Log("pannello 'journal': contenitore testo -> " .. table.concat(probe, ", "))
	DC_Log("pannello 'journal': voci inviate=" .. tostring(filled) ..
		" nella lista=" .. listed .. " | " .. table.concat(notes, ", "))

	DC_FullScreen(ui, root)
	ui:Show()
	return true
end

-- Voci-comando: "testo cliccabile".
--
-- Il filmato non ci avvisa dei click (lo sappiamo dal log: manda solo un
-- suono), pero' la lista tiene la propria selezione in chiaro e la si puo'
-- leggere. Quindi si guarda a ogni tick quale voce risulta scelta: se e' una
-- delle voci il cui id comincia per "cmd:", si esegue l'ordine invece di
-- limitarsi a mostrarne il testo. Ricordando l'ultima gestita, un comando non
-- riparte da solo finche' la selezione non cambia.
local function DC_ReadSelection(root)
	local list = nil
	pcall(function() list = root.journal_mc.tutorialList end)
	if list == nil then return nil end

	local gpos = nil
	pcall(function() gpos = list.m_CurrentSelection.list_pos end)
	if gpos == nil then return nil end

	local group = nil
	pcall(function() group = list.content_array[gpos] end)
	if group == nil then return nil end

	local gname = nil
	pcall(function() gname = tostring(group.gName) end)

	local ipos = nil
	pcall(function() ipos = group.list.m_CurrentSelection.list_pos end)

	local seen = tostring(gname) .. "/" .. tostring(ipos)
	if seen ~= dcSelProbed then
		dcSelProbed = seen
		DC_Log(string.format(
			"pannello 'journal': selezione gruppo=%s (pos %s) voce pos=%s",
			tostring(gname), tostring(gpos), tostring(ipos)))
	end

	if gname == nil or ipos == nil then return nil end
	local ids = dcEntryIds[string.upper(gname)]
	if ids == nil then
		DC_WarnOnce("nogroup", "pannello: gruppo '" .. tostring(gname) ..
			"' non e' tra quelli inseriti")
		return nil
	end
	-- Le liste Flash contano da zero, Lua da uno.
	return ids[ipos + 1]
end

local function DC_PollSelection()
	if not dcVisible then return end
	local ui = Ext.UI.GetByName(DC_JOURNAL_UI)
	if ui == nil then return end
	local root = ui:GetRoot()
	if root == nil then return end

	local id = DC_ReadSelection(root)
	if id == nil then return end
	if string.sub(id, 1, 4) ~= "cmd:" then
		dcLastCommand = nil
		return
	end
	if id == dcLastCommand then return end
	dcLastCommand = id

	local cmd = string.sub(id, 5)
	DC_Log("pannello: comando '" .. cmd .. "'")
	pcall(Ext.Net.PostMessageToServer, "DC_BoardCommand", cmd)
end

local function DC_JournalHide()
	local ui = Ext.UI.GetByName(DC_JOURNAL_UI)
	if ui == nil then return end
	pcall(function() ui:GetRoot().hideWin() end)
	pcall(function() ui:Hide() end)
end

-- ---------------------------------------------------------------------------
-- Apertura e chiusura

local function DC_HideAll()
	DC_JournalHide()
	dcVisible = false
end

local function DC_Show(data)
	if data == nil then return end
	dcPages = data
	dcVisible = DC_JournalShow(data) and true or false
end

-- Il battito che tiene vivo il pannello: esegue la chiusura chiesta dal
-- bottone X e legge la voce selezionata per le voci-comando. Sta QUI, dopo
-- DC_HideAll, perche' una funzione locale non esiste ancora per chi la
-- nomina piu' in alto nel file: agganciarlo prima lo lasciava senza effetto.
pcall(function()
	Ext.Events.Tick:Subscribe(function()
		if dcCloseRequest then
			dcCloseRequest = false
			DC_HideAll()
		end
		pcall(DC_PollSelection)
	end)
end)

Ext.RegisterNetListener("DC_ShowBoard2", function(_, payload)
	local ok, data = pcall(Ext.Json.Parse, payload)
	if not ok or type(data) ~= "table" then
		DC_Log("pannello: payload illeggibile: " .. tostring(data))
		return
	end
	DC_Show(data)
end)

-- Il canale vecchio resta agganciato: se qualcosa risponde ancora con il testo
-- unico, il pannello lo mostra invece di ignorarlo.
Ext.RegisterNetListener("DC_ShowBoard", function(_, payload)
	if dcPages ~= nil then return end
	DC_Show({ pages = { { id = "legacy", title = "Stats", group = "Stats",
		sections = { { title = "", header = { "" },
			rows = { { label = tostring(payload), values = {} } } } } } } })
end)

Ext.Events.RawInput:Subscribe(function(e)
	local input = e.Input
	if input == nil or input.Input == nil or input.Value == nil then return end
	local key = tostring(input.Input.InputId)
	if tostring(input.Value.State) ~= "Pressed" then return end

	if key == "escape" then
		if dcVisible then DC_HideAll() end
		return
	end

	-- Scorrimento della pagina del diario. La rotella arriva qui come input
	-- "wheel_ypos" / "wheel_yneg": la si usa direttamente, senza dipendere dal
	-- fatto che il filmato accetti o no gli eventi rotella per conto suo.
	if dcVisible then
		if key == "wheel_ypos" then
			DC_JournalScroll(-3)
			return
		elseif key == "wheel_yneg" then
			DC_JournalScroll(3)
			return
		elseif key == "pageup" then
			DC_JournalScroll(-6)
			return
		elseif key == "pagedown" then
			DC_JournalScroll(6)
			return
		elseif key == "up" then
			DC_JournalScroll(-1)
			return
		elseif key == "down" then
			DC_JournalScroll(1)
			return
		elseif key == "home" then
			-- Torna in cima: serve anche dopo aver cambiato voce, perche' il
			-- diario non ci avvisa quando l'utente ne clicca un'altra e il
			-- testo nuovo eredita lo scorrimento del precedente.
			DC_JournalScroll(-999)
			return
		end
	end

	if key ~= DC_TOGGLE_KEY then return end

	-- Fuori dalla partita (menu, caricamenti) il tasto non deve fare nulla.
	local okG, state = pcall(Ext.Client.GetGameState)
	if not okG or tostring(state) ~= "Running" then return end

	if dcVisible then
		DC_HideAll()
	else
		Ext.Net.PostMessageToServer("DC_RequestBoard2", "")
	end
end)
