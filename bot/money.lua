-- Exchange stackable currency through the native item-use path.
local money = {}

money.MACRO_PERIOD_MS = 1000
money.DEFAULT_ITEMS = { 3031, 3035 }

local function itemId(entry)
    if type(entry) == 'number' then return entry end
    if type(entry) == 'table' then return tonumber(entry.id) end
    return nil
end

local function configuredIds(storage)
    local entries = storage and storage.moneyItems
    if type(entries) ~= 'table' then
        entries = money.DEFAULT_ITEMS
        if storage then storage.moneyItems = entries end
    end

    local ids = {}
    for _, entry in ipairs(entries) do
        local id = itemId(entry)
        if id then ids[id] = true end
    end
    return ids
end

local function isLootContainer(bot, container)
    if container.lootContainer then return true end
    local targetbot = bot.modules and bot.modules.targetbot
    local loot = targetbot and targetbot.loot
    return loot and loot.isLootContainer and loot.isLootContainer[container.id] == true
end

local function itemForUse(container, item, slot)
    local wrapped = setmetatable({}, { __index = item })
    wrapped.containerId = container.id
    wrapped.slot = slot - 1
    wrapped.stackPos = slot - 1
    wrapped.absoluteSlot = (container.firstIndex or 0) + slot - 1
    wrapped.pos = { x = 0xFFFF, y = 0x40 + container.id, z = slot - 1 }
    return wrapped
end

function money.new(bot)
    if type(bot) ~= 'table' then error('money.new: bot instance required', 2) end

    local self = {
        bot = bot,
        api = bot.api,
        storage = bot.storage,
        macro = nil,
    }
    setmetatable(self, { __index = money })
    self.macro = bot:macro(money.MACRO_PERIOD_MS, 'Exchange money', function()
        self:tick()
    end)
    return self
end

function money:isOn()
    return self.macro and self.macro.isOn() or false
end

function money:setOn()
    if self.macro then self.macro.setOn() end
    return self
end

function money:setOff()
    if self.macro then self.macro.setOff() end
    return self
end

function money:tick()
    local ids = configuredIds(self.storage)
    for _, container in ipairs(self.api.getContainers()) do
        if not isLootContainer(self.bot, container) then
            for slot, item in ipairs(container.items or {}) do
                if item and item.count == 100 and ids[item.id] then
                    return self.api.use(itemForUse(container, item, slot))
                end
            end
        end
    end
end

return money
