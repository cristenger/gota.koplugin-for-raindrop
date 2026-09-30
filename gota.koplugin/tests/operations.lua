return function(test, equal, truthy, contains)
    local Operations = dofile("gota_operations.lua")
    local function trapper(execute)
        return {
            isWrapped = function() return true end,
            dismissableRunInSubprocess = function(_, task) return execute(task) end,
        }
    end

    test("operation worker returns nil-bearing tuples to the parent", function()
        local operations = Operations:new{ trapper = trapper(function(task) return true, task() end) }
        local a, b, c = operations:execute(function() return nil, "failure", 429 end, {method="GET"})
        equal(a, nil, "result")
        equal(b, "failure", "error")
        equal(c, 429, "status")
    end)

    test("cancelled downloads remove compressed and decoded temporary files", function()
        local path = os.tmpname()
        os.remove(path)
        assert(io.open(path .. ".part", "w")):close()
        assert(io.open(path .. ".part.decoded", "w")):close()
        local operations = Operations:new{ trapper = trapper(function() return false end) }
        local ok, err = pcall(operations.execute, operations, function() error("must not run") end,
            {method="GET", target_path=path})
        equal(ok, false, "whole operation aborted")
        truthy(err.gota_operation_cancelled, "cancellation marker")
        equal(io.open(path .. ".part", "r"), nil, "compressed part removed")
        equal(io.open(path .. ".part.decoded", "r"), nil, "decoded part removed")
    end)

    test("interrupted writes invalidate cache and explain uncertain outcome", function()
        local invalidated = 0
        local operations = Operations:new{
            trapper = trapper(function() return false end),
            invalidate = function() invalidated = invalidated + 1 end,
        }
        local ok, err = pcall(operations.execute, operations, function() end, {method="PUT"})
        equal(ok, false, "write flow aborted")
        equal(invalidated, 1, "parent invalidation")
        contains(err.message, "may have saved", "uncertain outcome")
    end)

    test("responses from a previous session are discarded", function()
        local generation, invalidated = 1, 0
        local operations = Operations:new{
            trapper = trapper(function(task)
                local results = task()
                generation = 2
                return true, results
            end),
            get_generation = function() return generation end,
            invalidate = function() invalidated = invalidated + 1 end,
        }
        local ok, err = pcall(operations.execute, operations,
            function() return {user="previous"} end, {method="GET"})
        equal(ok, false, "old response discarded")
        equal(invalidated, 1, "old cache cleared")
        contains(err.message, "account changed", "session error")
    end)

    test("operation entry point wraps callers and rejects overlapping work", function()
        local wrapped = 0
        local pending
        local trap = {
            isWrapped = function() return false end,
            wrap = function(_, callback) wrapped = wrapped + 1; pending = callback end,
        }
        local finished = 0
        local operations = Operations:new{trapper=trap, finish=function() finished=finished+1 end}
        local ran = 0
        operations:run(function() ran = ran + 1 end)
        equal(ran, 0, "caller waits for coroutine")
        equal(operations:run(function() ran = ran + 1 end), false, "overlap rejected")
        equal(wrapped, 1, "one operation")
        pending()
        equal(ran, 1, "task ran")
        equal(finished, 1, "progress cleaned")
        equal(operations.busy, false, "operation released")
    end)

    test("missing worker results never look like a successful write", function()
        local operations = Operations:new{trapper=trapper(function() return true end)}
        local result, err = operations:execute(function() end, {method="PUT"})
        equal(result, nil, "worker failed")
        contains(err, "may have saved", "uncertain outcome")
    end)

    test("cancelling optional metadata aborts the entire composite operation", function()
        local workers, finished, notified, rendered = 0, 0, 0, 0
        local operations = Operations:new{
            trapper = trapper(function(task)
                workers = workers + 1
                if workers == 2 then return false end
                return true, task()
            end),
            finish = function() finished = finished + 1 end,
            notify = function() notified = notified + 1 end,
        }
        local caller = coroutine.create(function()
            operations:run(function()
                local roots = operations:execute(function() return {items={}} end, {method="GET"})
                truthy(roots, "required roots received")
                -- Missing optional data ordinarily allows the caller to keep
                -- going. Cancellation must instead escape this whole flow.
                local user = operations:execute(function() return {user={}} end, {method="GET"})
                if not user then roots.warning = "groups unavailable" end
                operations:execute(function() return {items={}} end, {method="GET"})
                rendered = rendered + 1
            end)
        end)
        local ok, failure = coroutine.resume(caller)
        truthy(ok, tostring(failure))
        equal(coroutine.status(caller), "dead", "caller unwound after cancellation")
        equal(workers, 2, "child collections and stats never start")
        equal(rendered, 0, "partial menu never opens")
        equal(finished, 1, "dismissed progress cleaned once")
        equal(notified, 0, "ordinary cancellation is quiet")
        equal(operations.busy, false, "next operation can start")
        local next_caller = coroutine.create(function()
            return operations:run(function() return "next operation" end)
        end)
        local next_ok, result = coroutine.resume(next_caller)
        truthy(next_ok, "global lock released")
        equal(result, "next operation", "next operation succeeds")
    end)

    test("busy operations reject other wrapped coroutines and plugin instances", function()
        local trap = { isWrapped = function() return coroutine.running() ~= nil end }
        local finished, nested, overlap = 0, 0, 0
        local first = Operations:new{trapper=trap, finish=function() finished=finished+1 end}
        local second = Operations:new{trapper=trap}
        local owner = coroutine.create(function()
            return first:run(function()
                local result = first:run(function() nested = nested + 1; return 42 end)
                equal(result, 42, "same-owner nested result")
                coroutine.yield("worker pending")
                return 77
            end)
        end)
        local owner_ok, waiting = coroutine.resume(owner)
        truthy(owner_ok, "owner starts")
        equal(waiting, "worker pending", "parent yields while busy")
        local other = coroutine.create(function()
            equal(first:run(function() overlap = overlap + 1 end), false, "different wrapped coroutine")
            equal(second:run(function() overlap = overlap + 1 end), false, "other plugin instance")
        end)
        local other_ok, other_error = coroutine.resume(other)
        truthy(other_ok, tostring(other_error))
        equal(overlap, 0, "overlapping workers never run")
        equal(nested, 1, "nested entry point still works")
        equal(finished, 0, "owner remains in progress")
        local completed, result = coroutine.resume(owner)
        truthy(completed, "owner completes")
        equal(result, 77, "owner result preserved")
        equal(finished, 1, "owner releases once")
        equal(first.busy, false, "local lock released")
        equal(first.owner, nil, "coroutine owner cleared")
        local followup = coroutine.create(function()
            return second:run(function() return 91 end)
        end)
        local followup_ok, followup_result = coroutine.resume(followup)
        truthy(followup_ok, "global lock released")
        equal(followup_result, 91, "other instance can work afterwards")
    end)
end
