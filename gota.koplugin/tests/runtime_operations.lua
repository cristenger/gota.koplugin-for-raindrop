-- Run from KOReader's runtime directory with an isolated KO_HOME:
-- KO_HOME="$(mktemp -d)" ./luajit /path/gota.koplugin/tests/runtime_operations.lua
-- Uses real Trapper, LuaJIT, fork and IPC with a minimal UI scheduler.
assert(os.getenv("KO_HOME") and os.getenv("KO_HOME") ~= "",
    "Set KO_HOME to an isolated temporary directory")
require("setupkoenv")
local socket = require("socket")
local ffi = require("ffi")
require("ffi/posix_h")
local queue, ticks = {}, 0
local UI = {}
function UI:scheduleIn(delay, callback)
    queue[#queue+1] = {due=socket.gettime()+delay,callback=callback}
end
function UI:unschedule(callback)
    for i=#queue,1,-1 do if queue[i].callback==callback then table.remove(queue,i) end end
end
function UI:show() end
function UI:close() end
function UI:forceRePaint() end
function UI:preventStandby() end
function UI:allowStandby() end
package.loaded["ui/uimanager"] = UI
for _, name in ipairs({"confirmbox","infomessage","trapwidget"}) do
    package.loaded["ui/widget/"..name] = {new=function(_,options) return options end}
end
local Trapper = require("ui/trapper")
local source = debug.getinfo(1, "S").source
local plugin = arg[1] or source:match("^@(.+)/tests/runtime_operations%.lua$")
assert(plugin, "Pass an absolute plugin path as the first argument")
package.path=plugin.."/?.lua;"..package.path
local Operations=require("gota_operations")
local function drain(operations)
    local deadline=socket.gettime()+3
    while operations.busy do
        assert(socket.gettime()<deadline,"operation did not finish")
        local now=socket.gettime()
        for i=#queue,1,-1 do
            if queue[i] and queue[i].due<=now then
                local callback=table.remove(queue,i).callback
                ticks=ticks+1
                callback()
            end
        end
        socket.sleep(0.005)
    end
end
local parent=tonumber(ffi.C.getpid())
local result
local progress={}
local operations=Operations:new{trapper=Trapper,get_progress=function() return progress end,
    notify=function(text) error(text) end}
operations:run(function()
    result=operations:execute(function()
        socket.sleep(0.2)
        return {pid=tonumber(ffi.C.getpid()),value="worker result"}
    end,{method="GET"})
end)
assert(result==nil,"caller blocked instead of yielding")
drain(operations)
assert(result and result.pid~=parent and result.value=="worker result")
assert(ticks>0)
print("PASS real Trapper subprocess yielded and returned data")
local after_cancel=false
operations:run(function()
    UI:scheduleIn(0.03,function() progress.dismiss_callback() end)
    operations:execute(function() socket.sleep(1);return true end,{method="GET"})
    after_cancel=true
end)
drain(operations)
assert(after_cancel==false,"cancel continued the composite caller")
print("PASS real Trapper cancellation aborted the complete flow")
