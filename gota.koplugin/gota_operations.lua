-- Keep network work out of the UI process. Widgets and response caches remain
-- owned by the parent; the child returns plain data or an atomic download path.
local logger = require("logger")
local _ = require("gota_gettext")
local unpack = unpack or table.unpack

local Operations = {}
local active_operation

local function pack(...)
    return { n = select("#", ...), ... }
end

function Operations:new(options)
    options = options or {}
    local instance = setmetatable({}, { __index = self })
    instance.trapper = options.trapper or require("ui/trapper")
    instance.get_generation = options.get_generation or function() return 0 end
    instance.get_progress = options.get_progress or function() return nil end
    instance.finish = options.finish or function() end
    instance.notify = options.notify or function() end
    instance.invalidate = options.invalidate or function() end
    return instance
end

-- Entry points must wrap the whole caller, so it resumes with the worker's
-- result before building a menu or changing navigation.
function Operations:run(task)
    if self.busy and self.owner ~= nil and coroutine.running() == self.owner then return task() end
    if self.busy or active_operation then return false end
    self.busy = true
    active_operation = self
    local function perform()
        self.owner = coroutine.running()
        local results = pack(pcall(task))
        local ok, err = results[1], results[2]
        self.busy = false
        self.owner = nil
        active_operation = nil
        self.finish()
        if not ok then
            if type(err) == "table" and err.gota_operation_cancelled then
                if err.message then self.notify(err.message) end
            else
                logger.warn("Gota: operation failed:", tostring(err))
                self.notify(_("Could not complete the operation"))
            end
        end
        if ok then return unpack(results, 2, results.n) end
    end
    if self.trapper:isWrapped() then return perform() end
    return self.trapper:wrap(perform)
end

local function cleanupInterruptedDownload(path)
    if type(path) ~= "string" or path == "" then return end
    os.remove(path .. ".part")
    os.remove(path .. ".part.decoded")
end

function Operations:execute(task, context)
    context = context or {}
    if not self.trapper:isWrapped() then
        return nil, _("The network operation could not be started")
    end
    local generation = self.get_generation()
    local completed, results = self.trapper:dismissableRunInSubprocess(function()
        return pack(task())
    end, self.get_progress() or _("Connecting to Raindrop…"))

    local mutation = context.method ~= nil and context.method ~= "GET"
        and context.method ~= "HEAD"
    if not completed then
        cleanupInterruptedDownload(context.target_path)
        if mutation then
            self.invalidate()
            error({ gota_operation_cancelled = true,
                message = _("The operation was interrupted. Raindrop may have saved the change; reload the article before trying again.") }, 0)
        end
        -- Abort the whole caller, including optional follow-up endpoints and
        -- fallback article data. A dismissed widget must never be reused.
        error({ gota_operation_cancelled = true }, 0)
    end
    if generation ~= self.get_generation() then
        self.invalidate()
        error({ gota_operation_cancelled = true,
            message = _("The account changed during the operation; reopen Gota") }, 0)
    end
    if type(results) ~= "table" or type(results.n) ~= "number" then
        if mutation then self.invalidate() end
        return nil, mutation
            and _("No result was received. Raindrop may have saved the change; reload the article before trying again.")
            or _("No result was received from the network operation")
    end
    return unpack(results, 1, results.n)
end

return Operations
