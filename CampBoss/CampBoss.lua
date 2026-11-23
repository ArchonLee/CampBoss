local ADDON_NAME, ns = ...
ns = ns or {}
local DEFAULTS = { price = 50, paySeconds = 30, staySeconds = 180, channel = "YELL" }
local INVITE_SECONDS = 65
local TRADE_GRACE = 0.5

local frame = CreateFrame("Frame")
local events = {}
local db, running, terms, trade, nextTick, blocked
local pending, guests = {}, {}

local function say(text)
    DEFAULT_CHAT_FRAME:AddMessage("|cff68d7bdCampBoss|r " .. text)
end

local function safe(value, kind)
    return type(value) == kind and not (issecretvalue and issecretvalue(value))
end

local function integer(value, min, max)
    if type(value) == "string" then
        value = value:match("^%s*(%d+)%s*$") and tonumber(value)
    end
    if type(value) == "number" and value >= min and value <= max and value % 1 == 0 then
        return value
    end
end

local function normalizeChannel(value)
    if type(value) ~= "string" then return end
    value = value:match("^%s*(.-)%s*$"):upper()
    if value == "YELL" or value == "SAY" then return value end
    local number = integer(value, 1, 99)
    return number and tostring(number)
end

function ns.GetSettings()
    return {
        price = db.price,
        paySeconds = db.paySeconds,
        staySeconds = db.staySeconds,
        channel = db.channel,
        spellID = db.spellID,
        itemID = db.itemID,
        autoAccept = db.autoAccept,
    }
end

local function optionalID(value)
    if value == nil or (type(value) == "string" and value:match("^%s*$")) then return nil end
    return integer(value, 1, 2147483647) or false
end

function ns.SaveSettings(values)
    local price = integer(values.price, 1, 1000000)
    local paySeconds = integer(values.paySeconds, 1, 3600)
    local staySeconds = integer(values.staySeconds, 1, 3600)
    local channel = normalizeChannel(values.channel)
    local spellID, itemID = optionalID(values.spellID), optionalID(values.itemID)
    if not price then return false, "价格须为 1–1000000 银的整数。" end
    if not paySeconds then return false, "付款时限须为 1–3600 秒的整数。" end
    if not staySeconds then return false, "留队时长须为 1–3600 秒的整数。" end
    if not channel then return false, "聊天频道编号须为 1–99 的整数。" end
    if spellID == false then return false, "帐篷法术 ID 须为正整数或留空。" end
    if itemID == false then return false, "帐篷物品 ID 须为正整数或留空。" end
    db.price, db.paySeconds, db.staySeconds, db.channel = price, paySeconds, staySeconds, channel
    db.spellID, db.itemID, db.autoAccept = spellID, itemID, values.autoAccept == true
    if ns.UpdateTentButton then ns.UpdateTentButton() end
    return true, running and "已保存；营业设置下次开摊生效。" or "已保存。"
end

local function itemSpell(item)
    local getItemSpell = (C_Item and C_Item.GetItemSpell) or GetItemSpell
    if item and getItemSpell then
        local _, id = getItemSpell(item)
        if safe(id, "number") then return id end
    end
end

local function duration(seconds)
    return seconds % 60 == 0 and ("%d分钟"):format(seconds / 60) or seconds .. "秒"
end

local function key(name)
    if not safe(name, "string") or name == "" then
        return nil
    end
    local normalized = name:gsub("%s+", ""):lower()
    if not normalized:find("-", 1, true) and GetNormalizedRealmName then
        local realm = GetNormalizedRealmName()
        if safe(realm, "string") and realm ~= "" then
            normalized = normalized .. "-" .. realm:gsub("%s+", ""):lower()
        end
    end
    return normalized
end

local function nameOf(unit)
    local name, realm = UnitName(unit)
    if not safe(name, "string") or name == "" then
        return nil
    end
    if safe(realm, "string") and realm ~= "" and not name:find("-", 1, true) then
        return name .. "-" .. realm
    end
    return name
end

local function canManage()
    return not IsInRaid() and (not IsInGroup() or UnitIsGroupLeader("player"))
end

local function roster()
    local members = {}
    if not IsInRaid() then
        for i = 1, 4 do
            local unit = "party" .. i
            local guid, name = UnitGUID(unit), nameOf(unit)
            if safe(guid, "string") and name then
                members[guid] = name
            end
        end
    end
    return members
end

local function refresh(now)
    local members = roster()
    if IsInRaid() then
        return members
    end
    for guid in pairs(guests) do
        if not members[guid] then
            guests[guid] = nil
        end
    end
    for name, invitation in pairs(pending) do
        if now >= invitation.expires then
            pending[name] = nil
        end
    end
    for guid, name in pairs(members) do
        local normalized = key(name)
        if pending[normalized] then
            pending[normalized] = nil
            if not guests[guid] then
                guests[guid] = { due = now + terms.paySeconds }
                say(name .. " 已入队，" .. duration(terms.paySeconds) .. "内付款。")
            end
        end
    end
    return members
end

local function attempt(api, ...)
    if type(api) ~= "function" then
        return false
    end
    blocked = nil
    local ok, result = pcall(api, ...)
    return ok and result ~= false and not blocked
end

local function requestRemoval(guest, name)
    if guest.attempted then
        return
    end
    if not canManage() then
        if not guest.warned then
            say(name .. "：" .. guest.remove .. "。当前没有移除权限，请手动处理。")
            guest.warned = true
        end
        return
    end
    guest.attempted = GetTime()
    local ok = attempt(C_PartyInfo.UninviteUnit, name, guest.remove, true)
    if ok then
        say(name .. "：" .. guest.remove .. "，已请求移出队伍。")
    else
        say(name .. "：" .. guest.remove .. "，自动移除被拒绝，请手动处理。")
        guest.warned = true
    end
end

function ns.Announce()
    if not running then return false, "请先开始接单。" end
    local channel = terms.channel
    local number = tonumber(channel)
    if number and GetChannelName(number) == 0 then
        local message = "未加入聊天频道 " .. number .. "。"
        say(message)
        return false, message
    end
    local ad = ("经验帐篷已摆，%d银/次，进组后%s内交易，付款后留队%s。需要请密我。")
        :format(terms.price, duration(terms.paySeconds), duration(terms.staySeconds))
    local ok = attempt(C_ChatInfo.SendChatMessage, ad, number and "CHANNEL" or channel, nil, number)
    if not ok then
        say("客户端拒绝发送公告。请手动喊话：" .. ad)
        return false, "公告未发出，详见聊天框。"
    end
    return true, "已请求发送公告。"
end

function ns.Start()
    if not canManage() then
        local message = "请在单人状态或担任小队队长时启动。"
        say(message)
        return false, message
    end
    if not running then
        terms = ns.GetSettings()
        running = true
        say("已开始接单。/tent status 查看状态，/tent stop 停止。")
    end
    return ns.Announce()
end

function ns.Stop()
    running, terms, trade, pending, guests = nil, nil, nil, {}, {}
    say("已停止接单和自动移除；现有成员留在队伍中。")
    return true, "已停止接单。"
end

function ns.GetStatus()
    local rows, waiting, now = {}, 0, GetTime()
    if running then
        for _ in pairs(pending) do waiting = waiting + 1 end
        for guid, name in pairs(roster()) do
            local guest = guests[guid]
            if guest then
                rows[#rows + 1] = {
                    name = name,
                    status = guest.remove and "待移出" or (guest.paid and "已付款" or "待付款"),
                    seconds = not guest.remove and math.max(0, math.ceil(guest.due - now)) or nil,
                }
            end
        end
        table.sort(rows, function(a, b) return a.name < b.name end)
    end
    return running, waiting, rows
end

function events:CHAT_MSG_WHISPER(_, sender, _, _, _, _, flags)
    local normalized = key(sender)
    if not running or not normalized or normalized == key(nameOf("player"))
        or (safe(flags, "string") and (flags == "GM" or flags == "DEV")) or not canManage() then
        return
    end
    local now = GetTime()
    local members = refresh(now)
    if pending[normalized] then
        return
    end
    for _, name in pairs(members) do
        if key(name) == normalized then
            return
        end
    end
    local slots = GetNumSubgroupMembers()
    for _ in pairs(pending) do
        slots = slots + 1
    end
    if slots >= 4 or (C_PartyInfo.IsPartyFull and C_PartyInfo.IsPartyFull()) then
        return
    end
    pending[normalized] = { expires = now + INVITE_SECONDS }
    if not attempt(C_PartyInfo.InviteUnit, sender) then
        pending[normalized] = nil
        say("客户端拒绝自动邀请 " .. sender .. "。")
    end
end

function events:GROUP_ROSTER_UPDATE()
    if not running then
        return
    end
    if IsInRaid() then
        running, terms, trade, pending, guests = nil, nil, nil, {}, {}
        say("已转为团队，停止接单和自动移除。")
        return
    end
    refresh(GetTime())
end

function events:ADDON_ACTION_BLOCKED(addon)
    if safe(addon, "string") and addon == ADDON_NAME then
        blocked = true
    end
end
events.ADDON_ACTION_FORBIDDEN = events.ADDON_ACTION_BLOCKED

local function tradePartner(members)
    local guid = UnitGUID("npc")
    if not safe(guid, "string") then
        local name = nameOf("npc")
        if not name and TradeFrameRecipientNameText then
            name = TradeFrameRecipientNameText:GetText()
        end
        local target = key(name)
        if target then
            for memberGuid, member in pairs(members) do
                if key(member) == target then
                    guid = memberGuid
                    break
                end
            end
        end
    end
    if safe(guid, "string") and members[guid] then return guid end
end

function events:TRADE_SHOW()
    trade = nil
    if not running then return end
    local now = GetTime()
    local guid = tradePartner(refresh(now))
    if guid then
        local guest = guests[guid]
        if guest and not guest.paid and not guest.remove and now <= guest.due then
            trade = { guid = guid, guest = guest, balance = GetMoney() }
        end
    end
end

local function accepted(value)
    return (safe(value, "number") and value == 1) or (safe(value, "boolean") and value)
end

local function readTrade(api, ...)
    if type(api) ~= "function" then return false end
    return pcall(api, ...)
end

local function tryAccept(finished)
    if finished.attemptedAccept or not canManage() or GetTime() > finished.guest.due
        or finished.guest.remove or tradePartner(roster()) ~= finished.guid then
        return
    end
    local incomingOK, incoming = readTrade(GetTargetTradeMoney)
    local outgoingOK, outgoing = readTrade(GetPlayerTradeMoney)
    if not incomingOK or not safe(incoming, "number") then
        if not finished.warnedAccept then
            finished.warnedAccept = true
            say("无法读取对方报价，请在原生交易窗口核对并确认。")
        end
        return
    end
    if not (incoming >= terms.price * 100) or not outgoingOK
        or not safe(outgoing, "number") or outgoing ~= 0 then return end
    for slot = 1, 7 do
        local ok, name, texture, count, _, enchant, _, _, itemID = readTrade(GetTradePlayerItemInfo, slot)
        -- An occupied or enchanted slot is unsafe even if its item link is unavailable.
        if not ok or not safe(name, "nil") or not safe(texture, "nil")
            or not safe(enchant, "nil") or not safe(itemID, "nil")
            or (not safe(count, "nil") and (not safe(count, "number") or count ~= 0)) then
            return
        end
    end
    finished.attemptedAccept = true
    if not attempt(AcceptTrade) then
        say("客户端未允许自动确认，请在原生交易窗口核对并确认。")
    end
end

function events:TRADE_ACCEPT_UPDATE(playerAccepted, targetAccepted)
    if not trade or trade.closed then return end
    local playerReady, targetReady = accepted(playerAccepted), accepted(targetAccepted)
    trade.accepted = playerReady and targetReady
    if terms.autoAccept and not playerReady and targetReady
        and ((safe(playerAccepted, "boolean") and not playerAccepted)
            or (safe(playerAccepted, "number") and playerAccepted == 0)) then
        tryAccept(trade)
    end
end

local function settle(finished)
    if trade ~= finished then return end
    trade = nil
    local completed = finished.completed or finished.closed
    local guest = finished.guest
    local name = roster()[finished.guid]
    if guests[finished.guid] ~= guest or not name or guest.remove or completed > guest.due then
        return
    end
    local balance = GetMoney()
    if not safe(balance, "number") or not safe(finished.balance, "number") then
        say(name .. "：无法核验金币差额，仍按原付款时限处理。")
        return
    end
    local received = balance - finished.balance
    -- On Forever, a balance increase can confirm receipt even when no success message is exposed.
    if not finished.completed and received <= 0 then
        return
    end
    if received >= terms.price * 100 then
        guest.paid = true
        guest.due = completed + terms.staySeconds
        say(name .. " 已付款，保留" .. duration(terms.staySeconds) .. "。")
    else
        guest.remove = "实收不足" .. terms.price .. "银"
        requestRemoval(guest, name)
    end
end

function events:TRADE_CLOSED()
    if not trade or trade.closed then return end
    if not trade.accepted and not trade.completed then
        trade = nil
        return
    end
    local finished = trade
    finished.closed = GetTime()
    C_Timer.After(0.15, function() settle(finished) end)
end

function events:UI_INFO_MESSAGE(first, second)
    if not trade then return end
    local text = safe(second, "string") and second or first
    if not safe(text, "string") then return end
    if ERR_TRADE_CANCELLED and text == ERR_TRADE_CANCELLED then
        trade = nil
    elseif ERR_TRADE_COMPLETE and text == ERR_TRADE_COMPLETE then
        local now = GetTime()
        if not trade.closed or now - trade.closed <= TRADE_GRACE then
            trade.completed = trade.closed or now
        end
    end
end
function events:CHAT_MSG_SYSTEM(text)
    events:UI_INFO_MESSAGE(text)
end

function events:UNIT_SPELLCAST_SUCCEEDED(unit, _, spellID)
    if not safe(unit, "string") or unit ~= "player" or not db
        or not safe(spellID, "number")
        or (db.spellID ~= spellID and itemSpell(db.itemID) ~= spellID) then
        return
    end
    ns.Start()
end

local function tick()
    if not running then
        return
    end
    local now = GetTime()
    if nextTick and now < nextTick then
        return
    end
    nextTick = now + 0.2
    if trade and trade.closed and now - trade.closed > TRADE_GRACE then
        trade = nil
    end
    if IsInRaid() then
        events:GROUP_ROSTER_UPDATE()
        return
    end
    local members = refresh(now)
    for guid, guest in pairs(guests) do
        local confirming = trade and trade.guest == guest and trade.closed
            and (trade.completed or trade.closed) <= guest.due
        if not guest.remove and now >= guest.due and not confirming then
            guest.remove = guest.paid and (duration(terms.staySeconds) .. "已到")
                or (duration(terms.paySeconds) .. "内未收到付款")
        end
        if guest.remove then
            local name = members[guid]
            if name then
                requestRemoval(guest, name)
                if guest.attempted and not guest.warned and now - guest.attempted > 3 then
                    say(name .. " 仍在队伍中，请手动移除。")
                    guest.warned = true
                end
            end
        end
    end
end

local function command(input)
    local action, arg = input:match("^%s*(%S*)%s*(.-)%s*$")
    action = action:lower()
    if (action == "" or action == "show") and ns.TogglePanel then
        ns.TogglePanel(action == "show")
    elseif action == "start" then
        if not running then
            ns.Start()
        else
            say("已在接单；需要重喊请用 /tent announce。")
        end
    elseif action == "announce" then
        local ok, message = ns.Announce()
        if not ok and not running then say(message) end
    elseif action == "stop" then
        ns.Stop()
    elseif action == "status" then
        say((running and "正在接单" or "未接单") .. "；喊话频道："
            .. (terms or db).channel .. "；帐篷法术 ID：" .. (db.spellID or "未设置"))
        if running then
            local now = GetTime()
            local members = refresh(now)
            for guid, name in pairs(members) do
                local guest = guests[guid]
                if guest then
                    say(name .. "：" .. (guest.remove or
                        ((guest.paid and "已付款" or "待付款") .. "，剩余 "
                        .. math.max(0, math.ceil(guest.due - now)) .. "秒")))
                end
            end
        end
    elseif action == "channel" then
        local channel = normalizeChannel(arg)
        if channel then
            db.channel = channel
            say("已设置喊话频道：" .. channel .. (running and "（下次开摊生效）" or ""))
        else
            say("用法：/tent channel YELL、SAY 或聊天频道编号。")
        end
    elseif action == "spell" then
        local id = integer(arg, 1, 2147483647)
        if not id then
            say("用法：/tent spell 法术ID")
            return
        end
        db.spellID = id
        if ns.UpdateTentButton then ns.UpdateTentButton() end
        say("已设置帐篷法术 ID：" .. id)
    elseif action == "item" and arg ~= "" then
        local id = integer(arg, 1, 2147483647)
        if not id then say("用法：/tent item 物品ID"); return end
        db.itemID = id
        if ns.UpdateTentButton then ns.UpdateTentButton() end
        say("已设置帐篷物品 ID：" .. id)
    elseif action == "clearspell" or action == "clearitem" then
        if action == "clearspell" then db.spellID = nil else db.itemID = nil end
        if ns.UpdateTentButton then ns.UpdateTentButton() end
        say("已清除对应的帐篷 ID。")
    else
        say("/campboss show | start | stop | status | announce | channel | item | spell | clearitem | clearspell")
    end
end

function events:PLAYER_REGEN_ENABLED()
    if ns.UpdateTentButton then ns.UpdateTentButton() end
end

function events:ADDON_LOADED(addon)
    if addon ~= ADDON_NAME then
        return
    end
    if type(CampBossDB) ~= "table" then CampBossDB = {} end
    db = CampBossDB
    db.price = integer(db.price, 1, 1000000) or DEFAULTS.price
    db.paySeconds = integer(db.paySeconds, 1, 3600) or DEFAULTS.paySeconds
    db.staySeconds = integer(db.staySeconds, 1, 3600) or DEFAULTS.staySeconds
    db.channel = normalizeChannel(db.channel) or DEFAULTS.channel
    db.spellID = integer(db.spellID, 1, 2147483647)
    db.itemID = integer(db.itemID, 1, 2147483647)
    db.autoAccept = db.autoAccept == true
    SLASH_CAMPBOSS1 = "/campboss"
    SLASH_CAMPBOSS2 = "/tent"
    SlashCmdList.CAMPBOSS = command
    frame:UnregisterEvent("ADDON_LOADED")
end

for event in pairs(events) do
    frame:RegisterEvent(event)
end
frame:SetScript("OnEvent", function(_, event, ...)
    events[event](events, ...)
end)
frame:SetScript("OnUpdate", tick)
