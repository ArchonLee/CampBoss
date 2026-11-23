local _, ns = ...
local panel

local function inCombat()
    return InCombatLockdown and InCombatLockdown()
end

local function label(parent, text, template, x, y)
    local font = parent:CreateFontString(nil, "OVERLAY", template or "GameFontHighlight")
    font:SetPoint("TOPLEFT", x, y)
    font:SetText(text)
    return font
end

local function button(parent, text, x, y, width, onClick)
    local control = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    control:SetSize(width, 24)
    control:SetPoint("TOPLEFT", x, y)
    control:SetText(text)
    control:SetScript("OnClick", onClick)
    return control
end

local function numericInput(parent, x, y, width, length)
    local input = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
    input:SetSize(width, 22)
    input:SetPoint("TOPLEFT", x, y)
    input:SetAutoFocus(false)
    input:SetNumeric(true)
    input:SetMaxLetters(length)
    input:SetScript("OnEscapePressed", input.ClearFocus)
    input:SetScript("OnEnterPressed", input.ClearFocus)
    return input
end

local function divider(parent, y)
    local line = parent:CreateTexture(nil, "ARTWORK")
    line:SetPoint("TOPLEFT", 20, y)
    line:SetPoint("TOPRIGHT", -20, y)
    line:SetHeight(1)
    line:SetColorTexture(0.39, 0.47, 0.45, 0.45)
end

local function createPanel()
    local window = CreateFrame("Frame", nil, UIParent, BackdropTemplateMixin and "BackdropTemplate")
    window:SetSize(414, 484)
    window:SetPoint("CENTER")
    window:SetFrameStrata("DIALOG")
    window:SetClampedToScreen(true)
    window:SetMovable(true)
    if window.SetBackdrop then
        window:SetBackdrop({
            bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
            edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
            edgeSize = 24,
            insets = { left = 5, right = 5, top = 5, bottom = 5 },
        })
        window:SetBackdropColor(0.08, 0.12, 0.11, 0.97)
    else
        local background = window:CreateTexture(nil, "BACKGROUND")
        background:SetAllPoints()
        background:SetColorTexture(0.08, 0.12, 0.11, 0.97)
    end
    local header = CreateFrame("Frame", nil, window)
    header:SetPoint("TOPLEFT", 12, -6)
    header:SetPoint("TOPRIGHT", -38, -6)
    header:SetHeight(34)
    header:EnableMouse(true)
    header:RegisterForDrag("LeftButton")
    header:SetScript("OnDragStart", function() if not inCombat() then window:StartMoving() end end)
    header:SetScript("OnDragStop", function() window:StopMovingOrSizing() end)
    label(header, "CampBoss", "GameFontNormalLarge", 8, -8)
    local close = CreateFrame("Button", nil, window, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -5, -4)
    close:SetScript("OnClick", function() if not inCombat() then window:Hide() end end)

    local status = label(window, "", nil, 22, -53)
    local pending = label(window, "", "GameFontHighlightSmall", 22, -76)
    local feedback = label(window, "", "GameFontHighlightSmall", 22, -448)
    feedback:SetWidth(370)
    feedback:SetJustifyH("LEFT")

    local function report(_, message)
        feedback:SetText(message or "")
    end

    local render
    local toggle = button(window, "开始接单", 210, -51, 86, function()
        if ns.GetStatus() then report(ns.Stop()) else report(ns.Start()) end
        render()
    end)
    local announce = button(window, "发一条公告", 304, -51, 88, function()
        report(ns.Announce())
    end)
    local tent = CreateFrame("Button", nil, window, "SecureActionButtonTemplate,UIPanelButtonTemplate")
    tent:SetPoint("TOPLEFT", 304, -12)
    tent:SetSize(76, 24)
    tent:SetText("摆帐篷")
    tent:RegisterForClicks("LeftButtonDown", "LeftButtonUp")
    function ns.UpdateTentButton()
        if inCombat() then return end
        local saved = ns.GetSettings()
        tent:SetAttribute("item", saved.itemID and ("item:" .. saved.itemID) or nil)
        tent:SetAttribute("spell", saved.spellID)
        tent:SetAttribute("type", saved.itemID and "item" or (saved.spellID and "spell" or nil))
        if saved.itemID or saved.spellID then tent:Enable() else tent:Disable() end
    end

    divider(window, -98)
    local empty = label(window, "暂无顾客", "GameFontDisable", 22, -139)
    label(window, "顾客", "GameFontNormal", 22, -111)
    label(window, "状态", "GameFontNormal", 257, -111)
    label(window, "剩余", "GameFontNormal", 341, -111)
    local rows = {}
    for i = 1, 4 do
        local y = -136 - (i - 1) * 19
        local name = label(window, "", nil, 22, y)
        name:SetWidth(218)
        name:SetJustifyH("LEFT")
        name:SetWordWrap(false)
        rows[i] = { name, label(window, "", nil, 257, y), label(window, "", nil, 341, y) }
    end

    render = function()
        local active, waiting, guests = ns.GetStatus()
        status:SetText(active and "|cff78d4b0接单中|r" or "|cffaab5b1未接单|r")
        pending:SetText(("待入队邀请：%d"):format(waiting))
        toggle:SetText(active and "停止接单" or "开始接单")
        if active then announce:Enable() else announce:Disable() end
        if #guests == 0 then empty:Show() else empty:Hide() end
        for i, row in ipairs(rows) do
            local guest = guests[i]
            row[1]:SetText(guest and guest.name or "")
            row[2]:SetText(guest and guest.status or "")
            if guest and guest.seconds then
                row[3]:SetText(("%d:%02d"):format(math.floor(guest.seconds / 60), guest.seconds % 60))
            else
                row[3]:SetText("")
            end
        end
    end

    divider(window, -214)
    label(window, "营业设置", "GameFontNormal", 22, -227)
    label(window, "价格（银）", nil, 22, -250)
    label(window, "付款时限（秒）", nil, 149, -250)
    label(window, "留队时长（秒）", nil, 276, -250)
    local price = numericInput(window, 27, -269, 105, 7)
    local pay = numericInput(window, 154, -269, 105, 4)
    local stay = numericInput(window, 281, -269, 105, 4)

    label(window, "喊话频道", nil, 22, -309)
    local channelInput = numericInput(window, 328, -303, 58, 2)
    local channelMode, channels = nil, {}
    local function selectChannel(mode)
        channelMode = mode
        for value, control in pairs(channels) do
            if value == mode then control:LockHighlight() else control:UnlockHighlight() end
        end
        if mode == "CHANNEL" then
            channelInput:Show()
        else
            channelInput:ClearFocus()
            channelInput:Hide()
        end
    end
    channels.YELL = button(window, "大喊", 111, -302, 65, function() selectChannel("YELL") end)
    channels.SAY = button(window, "说话", 182, -302, 65, function() selectChannel("SAY") end)
    channels.CHANNEL = button(window, "编号频道", 253, -302, 65, function() selectChannel("CHANNEL") end)

    label(window, "帐篷法术 ID", nil, 22, -341)
    label(window, "帐篷物品 ID", nil, 211, -341)
    local spell = numericInput(window, 27, -361, 154, 10)
    local item = numericInput(window, 216, -361, 170, 10)
    local autoAccept = CreateFrame("CheckButton", nil, window, "UICheckButtonTemplate")
    autoAccept:SetPoint("TOPLEFT", 20, -399)
    autoAccept:SetSize(24, 24)
    label(autoAccept, "自动确认足额收款", nil, 25, -5)
    local function loadInputs()
        local saved = ns.GetSettings()
        price:SetText(tostring(saved.price))
        pay:SetText(tostring(saved.paySeconds))
        stay:SetText(tostring(saved.staySeconds))
        spell:SetText(tostring(saved.spellID or ""))
        item:SetText(tostring(saved.itemID or ""))
        autoAccept:SetChecked(saved.autoAccept)
        local number = tonumber(saved.channel)
        channelInput:SetText(number and tostring(number) or "")
        selectChannel(number and "CHANNEL" or saved.channel)
    end

    button(window, "保存设置", 304, -399, 88, function()
        local ok, message = ns.SaveSettings({
            price = price:GetText(),
            paySeconds = pay:GetText(),
            staySeconds = stay:GetText(),
            channel = channelMode == "CHANNEL" and channelInput:GetText() or channelMode,
            spellID = spell:GetText(),
            itemID = item:GetText(),
            autoAccept = not not autoAccept:GetChecked(),
        })
        if ok then loadInputs() end
        report(ok, message)
    end)

    window:SetScript("OnShow", function()
        loadInputs()
        feedback:SetText("")
        render()
    end)
    local elapsed = 0
    window:SetScript("OnUpdate", function(_, dt)
        elapsed = elapsed + dt
        if elapsed >= 0.2 then
            elapsed = 0
            render()
        end
    end)
    window:Hide()
    ns.UpdateTentButton()
    return window
end

function ns.TogglePanel(show)
    if inCombat() then return end
    panel = panel or createPanel()
    if show or not panel:IsShown() then panel:Show() else panel:Hide() end
end
