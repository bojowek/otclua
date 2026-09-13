-- Resolve an existing user profile or stock vBot configuration. No copying,
-- downloading, or directory creation: stock sources are mounted read-only.
local M = {}

local USER_STATE = {
    'storage',
    'vBot_configs',
    'cavebot_configs',
    'targetbot_configs',
}

local function normalise(path, trustedDefault)
    if type(path) ~= 'string' or path == '' then return nil end
    path = path:gsub('\\', '/'):gsub('/+$', '')
    if path:find('%z') then return nil end
    for part in path:gmatch('[^/]+') do
        if part == '..' and not trustedDefault then return nil end
    end
    return path
end

local function exists(path)
    local f = io.open(path, 'rb')
    if not f then return false end
    f:close()
    return true
end

-- opts.profileDir / opts.otRoot / opts.userDir are explicit and take precedence
-- over the corresponding environment variables. opts.defaultProfile is trusted
-- because it is selected by the launcher itself.
function M.resolve(opts)
    opts = opts or {}
    local getenv = opts.getenv or os.getenv
    local rawDir = opts.profileDir or getenv('LUACLIENT_VBOT_PROFILE')
    local rawRoot = opts.otRoot or getenv('LUACLIENT_VBOT_OTROOT')
    local rawUser = opts.userDir or getenv('LUACLIENT_VBOT_USERDIR')
    local dir = normalise(rawDir)
    local otRoot = normalise(rawRoot)
    local userDir = normalise(rawUser)

    if rawDir and not dir then return nil, 'invalid vBot profile directory' end
    if rawRoot and not otRoot then return nil, 'invalid otclient root directory' end
    if rawUser and not userDir then return nil, 'invalid vBot user directory' end

    if not dir and otRoot then
        local classic = otRoot .. '/profiles/bot/vBot_4.8'
        dir = exists(classic .. '/_Loader.lua') and classic
            or otRoot .. '/mods/game_bot/default_configs/vBot_4.8'
    end

    dir = dir or normalise(opts.defaultProfile, true)
    if not dir then
        return nil, 'specify --vbot-profile=DIR or --vbot-otroot=DIR (an existing local checkout)'
    end

    local parent, config = dir:match('^(.*)/([^/]+)$')
    if not parent or config == '.' or config:find(':', 1, true) then
        return nil, 'invalid vBot profile directory: ' .. dir
    end

    local stockRoot = parent:match('^(.*)/mods/game_bot/default_configs$')
    local profileRoot = parent:match('^(.*)/[Bb]ot$')
    if stockRoot then
        otRoot = otRoot or stockRoot
        profileRoot = otRoot .. '/profiles'
    elseif profileRoot then
        otRoot = otRoot or profileRoot:match('^(.*)/[^/]+$')
    else
        return nil, 'vBot profile must be under bot/ or mods/game_bot/default_configs/'
    end

    if not otRoot or otRoot == '' then
        return nil, 'cannot derive the otclient root; pass --vbot-otroot=DIR'
    end

    local overlays
    if stockRoot and userDir then
        profileRoot = userDir
        overlays = {}
        for _, name in ipairs(USER_STATE) do
            overlays[#overlays + 1] = '/bot/' .. config .. '/' .. name
        end
    end

    return {
        dir = dir,
        config = config,
        otRoot = otRoot,
        writeDir = profileRoot,
        stock = stockRoot ~= nil,
        mounts = stockRoot and { ['/bot/' .. config] = dir } or nil,
        overlays = overlays,
    }
end

return M
