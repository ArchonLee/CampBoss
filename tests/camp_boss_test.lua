local now, balance, partner, raid
local roster, invites, kicks, ads, timers, handlers, messages, channels

local function equal(actual, expected)
    assert(actual == expected, tostring(actual) .. " ~= " .. tostring(expected))
end

function CreateFrame()
    return {
        RegisterEvent = function() end,
        UnregisterEvent = function() end,
        SetScript = function(_, event, handler) handlers[event] = handler end,
    }
end

DEFAULT_CHAT_FRAME = { AddMessage = function() end }
ERR_TRADE_COMPLETE = "complete"
ERR_TRADE_CANCELLED = "cancelled"
function GetMoney() return balance end
function GetTime() return now end
function IsInRaid() return raid end
function IsInGroup() return #roster > 0 end
function GetNumSubgroupMembers() return #roster end
function UnitIsGroupLeader() return true end
function GetNormalizedRealmName() return "Realm" end
function UnitName(unit)
    if unit == "player" then return "Host" end
    return roster[tonumber(unit:match("^party(%d)$")) or 0]
end
function UnitGUID(unit)
    local name = unit == "npc" and partner or UnitName(unit)
    return name and "guid:" .. name
end
C_PartyInfo = {
    InviteUnit = function(name) invites[#invites + 1] = name end,
    UninviteUnit = function(name, reason) kicks[#kicks + 1] = { name, reason } end,
}
C_ChatInfo = { SendChatMessage = function(message, channel, _, number)
    ads[#ads + 1], messages[#messages + 1], channels[#channels + 1] = channel, message, number
end }
function GetChannelName(number) return number end
C_Timer = { After = function(delay, callback)
    timers[#timers + 1] = { due = now + delay, callback = callback }
end }

local function event(name, ...)
    handlers.OnEvent(nil, name, ...)
end

local function advance(at)
    now = at
    for i = #timers, 1, -1 do
        if timers[i].due <= now then
            table.remove(timers, i).callback()
        end
    end
    handlers.OnUpdate()
end

local function setup(start, saved, ns)
    now, balance, partner, raid = 0, 100000, nil, false
    roster, invites, kicks, ads, timers, handlers = { "Friend" }, {}, {}, {}, {}, {}
    messages, channels = {}, {}
    CampBossDB, SlashCmdList = saved, {}
    assert(loadfile("CampBoss/CampBoss.lua"))("CampBoss", ns)
    event("ADDON_LOADED", "CampBoss")
    equal(SLASH_CAMPBOSS1, "/campboss")
    equal(SLASH_CAMPBOSS2, "/tent")
    if start then SlashCmdList.CAMPBOSS("start") end
end

local function join(at)
    event("CHAT_MSG_WHISPER", "hi", "Friend-Realm")
    event("CHAT_MSG_WHISPER", "hi", "Guest-Realm")
    event("CHAT_MSG_WHISPER", "hi", "guest")
    equal(#invites, 1)
    advance(at)
    roster[2] = "Guest"
    event("GROUP_ROSTER_UPDATE")
end

local function openTrade(at, name)
    advance(at)
    partner = name or "Guest"
    event("TRADE_SHOW")
    event("TRADE_ACCEPT_UPDATE", 1, 1)
end

setup(true)
equal(ads[1], "YELL")
join(5)
openTrade(34.5)
balance = balance + 5000
event("TRADE_CLOSED")
event("UI_INFO_MESSAGE", 0, ERR_TRADE_COMPLETE)
advance(35)
equal(#kicks, 0)
advance(214.4)
equal(#kicks, 0)
advance(214.7)
equal(kicks[1][1], "Guest")
equal(kicks[1][2], "3分钟已到")
equal(#ads, 1)

setup(true)
join(0)
openTrade(8)
balance = balance + 4999
event("TRADE_CLOSED")
advance(8.3)
equal(kicks[1][2], "实收不足50银")

setup(true)
join(0)
openTrade(8)
event("CHAT_MSG_SYSTEM", ERR_TRADE_COMPLETE, "")
event("TRADE_CLOSED")
advance(8.3)
equal(kicks[1][2], "实收不足50银")

setup(true)
join(0)
openTrade(8)
event("TRADE_CLOSED")
event("UI_INFO_MESSAGE", 0, ERR_TRADE_CANCELLED)
advance(9)
equal(#kicks, 0)
advance(30)
equal(kicks[1][2], "30秒内未收到付款")

setup(true)
join(0)
openTrade(8, "Friend")
balance = balance + 5000
event("TRADE_CLOSED")
advance(30)
equal(kicks[1][1], "Guest")
equal(#kicks, 1)

setup(true)
join(0)
openTrade(29)
advance(30)
equal(kicks[1][2], "30秒内未收到付款")

setup(true)
join(0)
openTrade(8)
balance = balance + 5000
event("TRADE_CLOSED")
SlashCmdList.CAMPBOSS("stop")
advance(200)
equal(#kicks, 0)

setup(false)
SlashCmdList.CAMPBOSS("spell 1234")
event("UNIT_SPELLCAST_SUCCEEDED", "player", "cast", 1233)
equal(#ads, 0)
event("UNIT_SPELLCAST_SUCCEEDED", "player", "cast", 1234)
equal(#ads, 1)
advance(60)
equal(#ads, 1)

setup(false)
C_Item = { GetItemSpell = function(item)
    if item == 5678 then return "Tent", 1234 end
end }
SlashCmdList.CAMPBOSS("item 5678")
event("UNIT_SPELLCAST_SUCCEEDED", "party1", "cast", 1234)
equal(#ads, 0)
event("UNIT_SPELLCAST_SUCCEEDED", "player", "cast", 1234)
equal(#ads, 1)

local confirmations, incoming, outgoing, itemSlot = 0, 5000, 0, nil
GetTargetTradeMoney = function() return incoming end
GetPlayerTradeMoney = function() return outgoing end
GetTradePlayerItemInfo = function(slot)
    if slot == itemSlot then return "Item" end
end
AcceptTrade = function() confirmations = confirmations + 1 end

local function openUnconfirmedTrade(name, at)
    now = at or 8
    partner = name or "Guest"
    event("TRADE_SHOW")
end

setup(true)
join(0)
openUnconfirmedTrade()
event("TRADE_ACCEPT_UPDATE", 0, 1)
equal(confirmations, 0)

setup(true, { autoAccept = true })
join(0)
openUnconfirmedTrade("Friend")
event("TRADE_ACCEPT_UPDATE", 0, 1)
equal(confirmations, 0)
openUnconfirmedTrade()
event("TRADE_ACCEPT_UPDATE", 0, 0)
incoming = nil
event("TRADE_ACCEPT_UPDATE", 0, 1)
incoming = 4999
event("TRADE_ACCEPT_UPDATE", 0, 1)
incoming, outgoing = 5000, 1
event("TRADE_ACCEPT_UPDATE", 0, 1)
outgoing, itemSlot = 0, 7
event("TRADE_ACCEPT_UPDATE", 0, 1)
equal(confirmations, 0)
itemSlot = nil
partner = "Friend"
event("TRADE_ACCEPT_UPDATE", 0, 1)
equal(confirmations, 0)
partner = "Guest"
event("TRADE_ACCEPT_UPDATE", 0, 1)
event("TRADE_ACCEPT_UPDATE", 0, 1)
equal(confirmations, 1)
event("TRADE_ACCEPT_UPDATE", 1, 1)
balance = balance + 5000
event("TRADE_CLOSED")
advance(8.3)
equal(#kicks, 0)
advance(188.3)
equal(kicks[1][2], "3分钟已到")

setup(true, { autoAccept = true })
join(0)
openUnconfirmedTrade()
now = 31
event("TRADE_ACCEPT_UPDATE", 0, 1)
equal(confirmations, 1)
advance(31)
equal(kicks[1][2], "30秒内未收到付款")

setup(true, { autoAccept = true })
join(0)
openUnconfirmedTrade()
AcceptTrade = function()
    confirmations = confirmations + 1
    event("ADDON_ACTION_BLOCKED", "CampBoss")
end
event("TRADE_ACCEPT_UPDATE", 0, 1)
event("TRADE_ACCEPT_UPDATE", 0, 1)
equal(confirmations, 2)
event("TRADE_CLOSED")
advance(30)
equal(kicks[1][2], "30秒内未收到付款")

local ns = {}
setup(false, { price = 0, paySeconds = "oops", channel = "bogus" }, ns)
equal(ns.GetSettings().price, 50)
equal(ns.GetSettings().paySeconds, 30)
equal(ns.GetSettings().channel, "YELL")
local updated = { price = "75", paySeconds = "10", staySeconds = "40", channel = "2", spellID = "" }
equal(ns.SaveSettings(updated), true)
equal(CampBossDB.price, 75)
equal(ns.Start(), true)
equal(ads[1], "CHANNEL")
equal(channels[1], 2)
assert(messages[1]:find("75银/次，进组后10秒内交易，付款后留队40秒", 1, true))
join(0)
local active, pending, guests = ns.GetStatus()
equal(active, true)
equal(pending, 0)
equal(guests[1].seconds, 10)
updated.price, updated.paySeconds, updated.staySeconds = "90", "20", "60"
equal(ns.SaveSettings(updated), true)
updated.paySeconds = "0"
equal(ns.SaveSettings(updated), false)
equal(CampBossDB.paySeconds, 20)
openTrade(9)
balance = balance + 7500
event("TRADE_CLOSED")
advance(9.3)
local _, _, paid = ns.GetStatus()
equal(paid[1].status, "已付款")
equal(paid[1].seconds, 40)
advance(49.5)
equal(kicks[1][2], "40秒已到")
ns.Stop()
ns.Start()
assert(messages[2]:find("90银/次，进组后20秒内交易，付款后留队1分钟", 1, true))

local createCoreFrame = CreateFrame
local controls, inputs, window, tent, checkbox = {}, {}
local function mockWidget()
    local widget = { shown = true, scripts = {}, attrs = {} }
    for _, method in ipairs({
        "SetPoint", "SetSize", "SetHeight", "SetWidth", "SetJustifyH", "SetWordWrap",
        "SetFrameStrata", "SetClampedToScreen", "SetMovable", "EnableMouse", "RegisterForDrag",
        "SetAllPoints", "SetColorTexture", "SetAutoFocus", "SetNumeric", "SetMaxLetters",
        "ClearFocus", "LockHighlight", "UnlockHighlight", "RegisterForClicks",
    }) do
        widget[method] = function() end
    end
    widget.CreateTexture, widget.CreateFontString = mockWidget, mockWidget
    function widget:SetScript(script, handler) self.scripts[script] = handler end
    function widget:SetText(text) self.text = text end
    function widget:GetText() return self.text end
    function widget:SetChecked(value) self.checked = value end
    function widget:GetChecked() return self.checked end
    function widget:SetAttribute(key, value) self.attrs[key] = value end
    function widget:Enable() self.disabled = false end
    function widget:Disable() self.disabled = true end
    function widget:Hide() self.shown = false end
    function widget:IsShown() return self.shown end
    function widget:Show()
        self.shown = true
        if self.scripts.OnShow then self.scripts.OnShow(self) end
    end
    return widget
end

UIParent = {}
function CreateFrame(kind, name, parent, template)
    if not parent then return createCoreFrame() end
    local widget = mockWidget()
    if parent == UIParent then window = widget end
    if template == "UIPanelButtonTemplate" then controls[#controls + 1] = widget end
    if template == "SecureActionButtonTemplate,UIPanelButtonTemplate" then tent = widget end
    if kind == "CheckButton" then checkbox = widget end
    if kind == "EditBox" then inputs[#inputs + 1] = widget end
    return widget
end

ns = {}
setup(false, nil, ns)
assert(loadfile("CampBoss/UI.lua"))("CampBoss", ns)
SlashCmdList.CAMPBOSS("")
equal(window:IsShown(), true)
equal(inputs[1]:GetText(), "50")
equal(controls[2].disabled, true)
equal(tent.disabled, true)
equal(checkbox:GetChecked(), false)
inputs[1]:SetText("0")
controls[6].scripts.OnClick()
equal(CampBossDB.price, 50)
inputs[1]:SetText("65")
controls[5].scripts.OnClick()
equal(inputs[4]:IsShown(), true)
inputs[4]:SetText("3")
inputs[5]:SetText("1234")
controls[6].scripts.OnClick()
equal(CampBossDB.price, 65)
equal(CampBossDB.channel, "3")
equal(CampBossDB.spellID, 1234)
equal(tent.attrs.type, "spell")
equal(tent.attrs.spell, 1234)
inputs[6]:SetText("5678")
checkbox:SetChecked(true)
local combat = true
InCombatLockdown = function() return combat end
controls[6].scripts.OnClick()
equal(CampBossDB.itemID, 5678)
equal(CampBossDB.autoAccept, true)
equal(tent.attrs.type, "spell")
combat = false
event("PLAYER_REGEN_ENABLED")
equal(tent.attrs.type, "item")
equal(tent.attrs.item, "item:5678")
controls[1].scripts.OnClick()
equal(controls[1]:GetText(), "停止接单")
equal(controls[2].disabled, false)
equal(#ads, 1)
controls[2].scripts.OnClick()
equal(#ads, 2)
controls[1].scripts.OnClick()
equal(controls[2].disabled, true)
SlashCmdList.CAMPBOSS("")
equal(window:IsShown(), false)
SlashCmdList.CAMPBOSS("show")
equal(inputs[1]:GetText(), "65")

print("CampBoss tests passed")
