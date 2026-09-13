local dailyReward = {}
dailyReward.__index = dailyReward

local function eventOn(events, name, fn)
    if getmetatable(events) ~= nil then return events:on(name, fn) end
    return events.on(name, fn)
end

local function eventOff(events, handle)
    if getmetatable(events) ~= nil then return events:off(handle) end
    return events.off(handle)
end

local function copyItems(items)
    local result = {}
    for itemId, count in pairs(items or {}) do
        itemId, count = tonumber(itemId), tonumber(count)
        if itemId and count and itemId > 0 and count > 0 then
            result[math.floor(itemId)] = math.floor(count)
        end
    end
    return result
end

function dailyReward.new(client, opts)
    opts = opts or {}
    local self = setmetatable({
        client = client,
        itemId = tonumber(opts.itemId),
        bonusShrine = tonumber(opts.bonusShrine) or 0,
        pending = false,
        claimed = false,
        handles = {},
    }, dailyReward)
    local events = client.events
    self.handles[#self.handles + 1] = eventOn(events, 'dailyReward', function(data)
        self:_onData(data)
    end)
    self.handles[#self.handles + 1] = eventOn(events, 'rewardWall', function(wall)
        self:_onWall(wall)
    end)
    return self
end

function dailyReward:_onWall(wall)
    self.wall = wall
    if self.pending and self.data then self:_claimDefault() end
end

function dailyReward:_onData(data)
    self.data = data
    if self.pending then self:_claimDefault() end
end

function dailyReward:open()
    if self.pending then return nil, 'daily reward request already pending' end
    if not self.client.sender then return nil, 'no sender' end
    self.pending, self.claimed = true, false
    return self.client.sender:sendOpenRewardWall()
end

function dailyReward:_activeDay()
    if not self.wall then return nil end
    local day = tonumber(self.wall.dayStreakDay) or 1
    local days = tonumber(self.data and self.data.days) or 0
    if day < 1 or day > days then return nil end
    return day
end

function dailyReward:_claimDefault()
    if self.claimed or not self.data then return end
    if self.wall and self.wall.wasDailyRewardTaken ~= 0 then
        self.pending = false
        self.client.log.info('daily reward was already taken')
        return
    end
    local day = self:_activeDay()
    if not day then return end
    local reward = self.data.freeRewards and self.data.freeRewards[day]
    if not reward then return end

    local items = {}
    if reward.redeemMode == 1 then
        local selected
        for _, item in ipairs(reward.selectableItems or {}) do
            if self.itemId then
                if item.itemId == self.itemId then selected = item; break end
            elseif not selected then
                selected = item
            end
        end
        if self.itemId and not selected then
            self.client.log.warn('daily reward item %d is not available on day %d', self.itemId, day)
            return
        end
        if not selected or not selected.itemId or (reward.itemsToSelect or 0) < 1 then
            self.client.log.warn('daily reward day %d has no valid selectable item', day)
            return
        end
        items[selected.itemId] = reward.itemsToSelect
    end

    local ok, err = self.client.sender:sendGetRewardDaily(self.bonusShrine, copyItems(items))
    if not ok then
        self.client.log.warn('daily reward claim failed: %s', tostring(err))
        return
    end
    self.claimed, self.pending = true, false
    self.client.log.info('daily reward claimed for day %d', day)
end

function dailyReward:claim(items, bonusShrine)
    if not self.client.sender then return nil, 'no sender' end
    local ok, err = self.client.sender:sendGetRewardDaily(
        tonumber(bonusShrine) or self.bonusShrine, copyItems(items))
    if ok then self.claimed, self.pending = true, false end
    return ok, err
end

function dailyReward:close()
    for _, handle in ipairs(self.handles) do eventOff(self.client.events, handle) end
    self.handles = {}
end

return dailyReward
