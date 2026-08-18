local superStatHeaders = {
    "Names:\t\t\t\t\t",
    "Damage Dealt:\t\t\t",
    "Damage Received:\t\t\t",
    "Healing Dealt:\t\t\t\t",
    "-------------------------------------------------",
    "Kills:\t\t\t\t\t",
    "Deaths:\t\t\t\t\t",
    "-------------------------------------------------",
    "Hits Dealt:\t\t\t\t",
    "Hits Received:\t\t\t\t",
    "-------------------------------------------------",
    "Critical Hits Dealt:\t\t\t",
    "Critical Damage Dealt:\t\t",
    "Critical Hits Received:\t\t",
    "Critical Damage Received:\t",
    "-------------------------------------------------",
    "Surface Damage Dealt:\t\t",
    "Surface Damage Received:\t",
    "Surface Hits Dealt:\t\t\t",
    "Surface Hits Received:\t\t",
    "-------------------------------------------------",
    "Status Damage Dealt:\t\t",
    "Status Hits Dealt:\t\t\t",
    "Status Damage Received:\t",
    "Status Hits Received:\t\t",
    "-------------------------------------------------",
    "Your Misses:\t\t\t\t",
    "Misses by Opponents:\t\t", 
    "-------------------------------------------------",
    "Blocks Performed:\t\t\t",
    "Attacks Blocked:\t\t\t",
    "Reflect Damage Received:\t",
    "-------------------------------------------------",
    "Damage Skills Used:\t\t",
    "Damage Skills Dealt:\t\t",
    "Damage Skills Received:\t\t",
    "-------------------------------------------------",
    "Highest Damage Hit:\t\t",
    "-------------------------------------------------",
    "Kill/Death Ratio:\t\t\t",
    "Critical Hit Rate:\t\t\t",
    "Miss Rate:\t\t\t\t",
    "Average Damage per Hit:\t",
    "-------------------------------------------------",
    "Item Destroyed:\t\t\t",
    "Looted Corpses:\t\t\t"
}

local Epip = Mods.EpipEncounters.Epip ---@type Epip
Epip.ImportGlobals(_G) -- The chance of this overriding any of your globals is low but never 0; safest approach is to explicitly import only the necessary ones

local Generic = Client.UI.Generic
local TextPrefab = Generic.GetPrefab("GenericUI_Prefab_Text") -- Provides a more convenient way of creating Text-type elements.
local CloseButtonPrefab = Generic.GetPrefab("GenericUI_Prefab_CloseButton") -- A button that automatically calls `UI:Hide()` on click.
local DragAreaPrefab = Generic.GetPrefab("GenericUI_Prefab_DraggingArea") -- An invisible rectangular area that allows dragging the UI around the screen with the mouse.
local Textures = Epip.GetFeature("Feature_GenericUITextures").TEXTURES -- Collection of UI built-in textures.
local V = Vector.Create

local myuistats = {}
local headerNames = nil

---@class MyUI : GenericUI_Instance
local UI = Generic.Create("MyUI")
UI.STAT_SIZE = V(550, 40)


---Creates the elements of the UI.
function UI._Initialize()
    if UI._Initialized then return end

    local panel = UI:CreateElement("Panel", "GenericUI_Element_Texture")
    panel:SetTexture(Textures.PANELS.CLIPBOARD_LARGE)

    local header = TextPrefab.Create(UI, "Header", panel, "Statistics", "Center", UI.STAT_SIZE)
    header:SetText(Text.Format("Statistics ", {Color = Color.BLACK, Size = "+5", FontType = Text.FONTS.BOLD}))
    header:SetPositionRelativeToParent("Top", 0, 80) 

    headerNames = TextPrefab.Create(UI, "Headernames", panel, "headernames", "Left", UI.STAT_SIZE)
    headerNames:SetText(Text.Format("--", {Color = Color.BLACK}))
    headerNames:SetPositionRelativeToParent("TopLeft", 120, 125)

    -- Make the top area of the UI draggable with mouse
    DragAreaPrefab.Create(UI, "DragArea", panel, V(panel:GetWidth(), 150))

    --local statsList = panel:AddChild("StatsList", "GenericUI_Element_VerticalList")
    --statsList:SetElementSpacing(-12)

    local closeButton = CloseButtonPrefab.Create(UI, "CloseButton", panel)
    closeButton:SetPositionRelativeToParent("TopRight", -40, 53)


    local statsList = panel:AddChild("StatsList", "GenericUI_Element_ScrollList")
    statsList:SetSize(600, 800)
    statsList:SetPositionRelativeToParent("Top", 0, 150)
    statsList:SetMouseWheelEnabled(true)
    statsList:SetElementSpacing(0)

    for i = 1, #superStatHeaders do
        local statName = "Stat" .. i
        UI["My" .. statName] = TextPrefab.Create(UI, statName, statsList, "", "Left", UI.STAT_SIZE)
        table.insert(myuistats, UI["My"..statName])
    end

    statsList:RepositionElements()
    --statsList:SetPositionRelativeToParent("Center") 

    UI._Initialized = true
    UI:Hide()
end


local function calculateMaxWidth(datas)
    local maxWidth = 0
    for i, row in ipairs(datas) do
        for j, value in ipairs(row) do
            value = tostring(value)
            maxWidth = math.max(maxWidth, string.len(value))
        end
    end
    return maxWidth
end

local function formatRow(row, maxWidth)
    local formattedRow = {}
    for i, value in ipairs(row) do
        value = tostring(value)
        local numSpacesNeeded = maxWidth - string.len(value)
        local numTabs = math.ceil(numSpacesNeeded / 8) + 1
        table.insert(formattedRow, value .. string.rep("\t", numTabs))
    end
    return table.concat(formattedRow, "")
end


local function formatDataForUI(datas)
    local maxWidth = calculateMaxWidth(datas)
    local formattedData = {}
    for _, row in ipairs(datas) do
        table.insert(formattedData, formatRow(row, maxWidth))
    end
    return formattedData
end


function UI.SetCharacter(datas)
    local formattedData = formatDataForUI(datas)
    local statHeaders = superStatHeaders
    local uiElements = myuistats
    local dataIndex = 2

    -- Assegna i valori usando un loop
    for i, statHeader in ipairs(statHeaders) do
        if i == 1 then
            headerNames:SetText(Text.Format(statHeader .. (formattedData[i] or ""), {Color = Color.BLACK}))
        elseif statHeader == "-------------------------------------------------" then
            if uiElements[i] then
                --uiElements[i]:SetText(Text.Format(statHeader, {Color = Color.BLACK}))
            end
        else
            if uiElements[i] and formattedData[dataIndex] then
                local text = Text.Format(statHeader .. (formattedData[dataIndex] or ""), {Color = Color.BLACK})
                uiElements[i]:SetText(text)
                dataIndex = dataIndex + 1  -- Incrementa solo se non è un separatore
            elseif uiElements[i] then
                -- Gestisci il caso in cui mancano dati
                uiElements[i]:SetText(Text.Format(statHeader, {Color = Color.BLACK}))
            end
        end
    end
   
end



-- Open the UI when a character is examined.
Client.UI.Examine.Events.Opened:Subscribe(function (_)
    local char = Client.UI.Examine.GetCharacter()
    local localChar = Client.GetCharacter()
    Ext.Net.PostMessageToServer("examineContest", localChar.MyGuid)
    
    UI:Show()
end)

local function tokenize(receivedDataString)
    local messageLines = {}
    for line in string.gmatch(receivedDataString, "[^@]+") do
        table.insert(messageLines, {})
        for value in string.gmatch(line, "[^,]+") do
            table.insert(messageLines[#messageLines], value)
        end
    end
    return messageLines
end

Ext.RegisterNetListener("PlayerStats", function(channel, payload)
    UI.SetCharacter(tokenize(payload))
end)

-- Initialize the UI's elements when the session loads
-- This cannot be done during bootstrap.
GameState.Events.GameReady:Subscribe(function (_)
    UI._Initialize()
end)

-- Close the UI when escape is pressed
Client.Input.Events.KeyPressed:Subscribe(function (ev)
    if ev.InputID == "escape" then
        UI:TryHide()
    end
end)


--[[
    PANELS = {
            ATTRIBUTES = T("PIP_UI_Panel_Attributes", {
                GUID = "c5c618ed-2bad-4677-a692-e8a4b68ca077",
            }),
            CONNECTIVITY = T("PIP_UI_Panel_Connectivity", {
                GUID = "66c99298-6b56-4edc-b764-939459a8b3a6",
            }),
            CLIPBOARD = T("PIP_UI_Panel_Clipboard", {
                GUID = "de3756f6-4566-4be0-95b5-42f2b7706d68",
            }),
            CLIPBOARD_SMALL = T("PIP_UI_Panel_Clipboard_Small", {
                GUID = "6624ce8e-4acd-4e3d-99e9-8efb8d34c3dc",
            }),
            CLIPBOARD_HEADERED = T("PIP_UI_Panel_Clipboard_Headered", {
                GUID = "67f908d0-04bf-4718-9c43-443f9f8fe4cb",
            }),
            CLIPBOARD_HEADERED_WITH_ICON_NO_PAPER = T("PIP_UI_Panel_Clipboard_Headered_WithIcon_NoPaper", {
                GUID = "b5a70373-276d-496f-bdd3-4b3744698add",
            }),
            CLIPBOARD_LARGE = T("PIP_UI_Panel_Clipboard_Large", {
                GUID = "c416e67c-439b-4527-937a-cc96cf9c93e8",
            }),
            DUAL_ROW = T("PIP_UI_Panel_DualRow", {
                GUID = "d285a27c-4010-45fd-806e-b13a0f2dcb33",
            }),
            DIALOGUE_CONTROLLER = T("PIP_UI_Panel_Dialogue_Controller", {
                GUID = "3ec1cc16-61f4-4a55-a4cb-fb0b994d6ad4",
            }),
            DIPLOMACY = T("PIP_UI_Panel_Diplomacy", {
                GUID = "bc439685-4da4-4e38-b1d3-745840f6dd96",
            }),
            DOS1_EXAMINE = T("PIP_UI_Panel_Examine_DOS1", {
                GUID = "d1bd56a1-faed-45b4-870c-4310cbfd7672",
            }),
            FLIPBOOK = T("PIP_UI_Panel_Flipbook", {
                GUID = "274e6019-48b3-4616-bbe1-f92b654978ff",
            }),
            GAME_MENU = T("PIP_UI_Panel_GameMenu", {
                GUID = "1efd93d3-0a2b-4af9-ae71-7809907a5ac0",
            }),
            LEGEND = T("PIP_UI_Panel_Legend", {
                GUID = "696b5050-16ff-4d7a-a151-f80d3a8065f5",
            }),
            LEGEND_SMALL = T("PIP_UI_Panel_Legend_Small", {
                GUID = "77ca66a4-b593-4383-b69e-4a937f6152ac",
            }),
            LOAD = T("PIP_UI_Panel_Load", {
                GUID = "a0a41f2c-4c87-438d-b5f7-ce82e0b1abfb",
            }),
            MODS = T("PIP_UI_Panel_Mods", {
                GUID = "2f3f8d74-c893-43ec-8af7-23131a028ab6",
            }),
            MODS_CONTROLLER = T("PIP_UI_Panel_Mods_Controller", {
                GUID = "d8bc3ed7-4564-4759-90b8-f92c2d864adc",
            }),
            REWARDS_CONTROLLER = T("PIP_UI_Panel_Reward_Controller", {
                GUID = "16ed65db-4642-4671-bcc4-f67d00f4f026",
            }),
            NOTE_CONTROLLER = T("PIP_UI_Panel_Note_Controller", {
                GUID = "6cc944eb-92e2-46d8-a360-f4454b0be1da",
            }),
            SKILLBOOK = T("PIP_UI_Panel_SkillBook", {
                GUID = "e4214879-bc18-4e72-94eb-fb3617d8d212",
            }),
            SKILLBOOK_KBM = T("PIP_UI_Panel_SkillBook_KBM", {
                GUID = "c7d39a28-c306-4d33-bbb1-0be6b2f53733",
            }),
            SETTINGS_LEFT = T("PIP_UI_Panel_Settings_Left", {
                GUID = "61e915dd-0a76-4496-ae30-864ff029bd98",
            }),
            SETTINGS_RIGHT = T("PIP_UI_Panel_Settings_Right", {
                GUID = "dfcaa132-be0d-4f01-9c0e-4a35abcbe5e6",
            }),
            LIST = T("PIP_UI_Panel_List", {
                GUID = "f3e1f7d5-bb6e-464f-b51d-ebe4adfd247a",
            }),
            MESSAGE_BOX_INPUT = T("PIP_UI_Panel_MessageBox_Input", {
                GUID = "9905eb39-449e-4cf9-a326-ef7f429f8c1e",
            }),
            MESSAGE_BOX = T("PIP_UI_Panel_MessageBox_Message", {
                GUID = "2bb72a22-8e00-48d2-b2b1-d5fece3e381f",
            }),
            TALL_PAGE = T("PIP_UI_Panel_TallPage", {
                GUID = "21cffdb1-4eb3-49c5-9584-48b8d4536d59",
            }),
            TALL_PAGE_SCROLLABLE = T("PIP_UI_Panel_TallPage_Scrollable", {
                GUID = "0cb61cd9-ca1a-4a75-9e9c-d11cf211d119",
            }),
            TALL_PAGE_SPLIT = T("PIP_UI_Panel_TallPage_Split", {
                GUID = "fdcba990-0c20-416c-a8ec-921d78640c64",
            }),
            TALL_PAGE_PORTRAIT = T("PIP_UI_Panel_TallWithPortrait", {
                GUID = "7b677843-dde9-49b2-bd13-8b7d78575ff1",
            }),
            PAGE_OUTLINE = T("PIP_UI_Panel_PageOutline", {
                GUID = "4e82a6ee-a0e6-4734-b2d7-bc18f78ec008",
            }),
            ALERT_TALL_CONTROLLER = T("PIP_UI_Panel_TallAlert_Controller", {
                GUID = "90fdb97a-48c2-4bfd-9eca-9df2ca866c19",
            }),
            ITEM_ALERT = T("PIP_UI_Panel_ItemAlert", {
                GUID = "1273b752-6d9b-4648-aecf-6bea0e56d94e",
            }),
            ITEM_ALERT_CONTROLLER = T("PIP_UI_Panel_ItemAlert_Controller", {
                GUID = "8269d380-4e4a-4f88-b375-e06f653d25c7",
            }),
            JOURNAL = T("PIP_UI_Panel_Journal", {
                GUID = "e77791ae-26b5-483a-8a94-a2f1aa42fcdf",
            }),
            PROMPT_CONTROLLER = T("PIP_UI_Panel_Prompt_Controller", {
                GUID = "3a5647b6-9e61-451e-a80b-4a6ea3ffbc21",
            }),
]]