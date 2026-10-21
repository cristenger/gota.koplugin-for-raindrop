return function(test, equal, truthy, contains)
    -- The main suite replaces package.loaded.gota_api for UI tests. Always
    -- exercise the implementation here rather than that stand-in.
    local API = dofile("gota_api.lua")
    local TLS = dofile("gota_tls.lua")

    local function settings(token)
        return {
            token = token or "account-a",
            getToken = function(self) return self.token end,
            setToken = function(self, value) self.token = value end,
        }
    end

    test("Trash explicitly PUTs collection -99 after concurrent remote movement", function()
        local api = API:new(settings())
        local method, body
        function api:makeRequest(_, value, payload)
            method, body = value, payload
            return { result = true, item = { _id = 7, collection = { ["$id"] = -99 } } }
        end
        truthy(api:trashRaindrop(7, 42), "move from stale local collection")
        equal(method, "PUT", "safe method")
        contains(body, '"$id":-99', "explicit Trash destination")
        equal(api:trashRaindrop(7, -99), nil, "already trashed")
    end)

    test("changing a token invalidates cached account responses", function()
        local config = settings()
        local api = API:new(config)
        local calls = 0
        function api:makeRequest()
            calls = calls + 1
            return { result = true, user = { name = config.token } }
        end
        equal(api:getUser().user.name, "account-a")
        equal(api:getUser().user.name, "account-a")
        equal(calls, 1, "cached first account")
        config:setToken("account-b")
        equal(api:getUser().user.name, "account-b")
        equal(calls, 2, "new account fetched")
        equal(api.session_generation, 1, "session generation")
    end)

    test("cache insertion removes all expired entries and evicts least recently used", function()
        local api = API:new(settings())
        api.cache_max_entries = 2
        function api:makeRequest(endpoint) return { value = endpoint } end
        api:cachedRequest("/a")
        api:cachedRequest("/b")
        api:cachedRequest("/a")
        api:cachedRequest("/c")
        truthy(api.response_cache["/a"], "recently used entry")
        equal(api.response_cache["/b"], nil, "least recently used entry")
        api.response_cache["/a"].timestamp = os.time() - api.cache_ttl - 1
        api.response_cache["/c"].timestamp = os.time() - api.cache_ttl - 1
        api:cachedRequest("/d")
        equal(api.response_cache["/a"], nil, "expired a")
        equal(api.response_cache["/c"], nil, "expired c")
        equal(api.cache_entry_count, 1, "live count")
    end)

    test("cache budget rejects oversized decoded tables and handles cycles", function()
        local api = API:new(settings())
        api.cache_max_bytes = 1024
        function api:makeRequest(endpoint)
            if endpoint == "/large" then return { value = string.rep("x", 1024) } end
            local result = { value = "small" }
            result.circular = result
            return result
        end
        truthy(api:cachedRequest("/large"), "uncached result still usable")
        equal(api.response_cache["/large"], nil, "oversized entry omitted")
        for index = 1, 8 do api:cachedRequest("/small" .. index) end
        truthy(api.cache_size_bytes <= api.cache_max_bytes, "bounded bytes")
        truthy(api.cache_entry_count <= api.cache_max_entries, "bounded count")
        equal(api.cache_entry_count, 1, "budget evicts older cyclic entries")
    end)

    test("server wait is reported uncapped", function()
        equal(API.serverWaitSeconds({ ["Retry-After"] = "120" }, 1000), 120, "Retry-After seconds")
        equal(API.serverWaitSeconds({ ["X-RateLimit-Reset"] = "1060" }, 1000), 60, "documented UTC reset")
        equal(API.serverWaitSeconds({ ["X-RateLimit-Reset"] = "990" }, 1000), 1, "elapsed reset waits briefly")
        equal(API.serverWaitSeconds({}, 1000), nil, "no rate-limit headers")
    end)

    test("429 message shows the server wait, not the worker budget", function()
        API.clearRateLimit()
        local api = API:new(settings())
        function api:_performRequest()
            return '{"result":false}', nil, 429, { ["Retry-After"] = "120" }
        end
        local _, err = api:makeRequest("/user")
        contains(err, "120", "real server wait")
        API.clearRateLimit()
    end)

    -- The executor runs in a forked subprocess whose memory is discarded, so
    -- anything the request records in module state must reach the parent
    -- through the returned values. Simulate that loss after each task.
    local function subprocessExecutor(counter)
        return function(task)
            counter.runs = counter.runs + 1
            local results = { n = 0 }
            local function pack(...) return { n = select("#", ...), ... } end
            results = pack(task())
            API.clearRateLimit()
            return unpack(results, 1, results.n)
        end
    end

    test("a recorded rate limit blocks the next request without network", function()
        API.clearRateLimit()
        local api = API:new(settings())
        local counter, calls = { runs = 0 }, 0
        function api:makeRequest()
            calls = calls + 1
            return nil, "rate limited", 429, { ["Retry-After"] = "120" }
        end
        api.sleep = function() end
        api:setRequestExecutor(subprocessExecutor(counter))
        local first = api:makeRequestWithRetry("/user")
        equal(first, nil, "rate limited")
        local second, err = api:makeRequestWithRetry("/collections")
        equal(second, nil, "blocked")
        equal(calls, 1, "no second HTTP request")
        equal(counter.runs, 1, "no second subprocess")
        contains(err, "rate limit", "explains the wait")
        API.clearRateLimit()
    end)

    test("a 429 on a mutation is not retried and still sets the cooldown", function()
        API.clearRateLimit()
        local api = API:new(settings())
        local calls = 0
        function api:makeRequest()
            calls = calls + 1
            return nil, "rate limited", 429, { ["X-RateLimit-Reset"] = tostring(os.time() + 60) }
        end
        api.sleep = function() end
        api:setRequestExecutor(subprocessExecutor({ runs = 0 }))
        equal(api:makeRequestWithRetry("/raindrop/1", "PUT", { important = true }), nil, "write failed")
        equal(calls, 1, "write sent once")
        equal(api:makeRequestWithRetry("/user"), nil, "read blocked")
        equal(calls, 1, "no request during the cooldown")
        API.clearRateLimit()
        api:makeRequestWithRetry("/user")
        equal(calls, 2, "cleared cooldown allows requests")
        API.clearRateLimit()
    end)

    test("a skewed device clock cannot lock Gota out for hours", function()
        -- E-readers often wake with a clock far behind Raindrop's; its reset
        -- epoch then looks hours away although the window is one minute.
        local wait = API.serverWaitSeconds({ ["X-RateLimit-Reset"] = tostring(1000 + 86400) }, 1000)
        truthy(wait <= 120, "reset-derived wait bounded: " .. tostring(wait))
        API.clearRateLimit()
        local api = API:new(settings())
        function api:makeRequest()
            return nil, "rate limited", 429, { ["X-RateLimit-Reset"] = tostring(os.time() + 86400) }
        end
        api:makeRequestWithRetry("/user")
        local remaining = API.rateLimitWait(nil, "account-a")
        truthy(remaining and remaining <= 120, "recorded cooldown bounded: " .. tostring(remaining))
        equal(API.rateLimitWait(os.time() - 3600, "account-a"), nil, "clock moved back: cooldown dropped")
        API.clearRateLimit()
    end)

    test("a rate limit on one token does not block testing another", function()
        API.clearRateLimit()
        local limited = API:new(settings("account-a"))
        function limited:makeRequest()
            return nil, "rate limited", 429, { ["Retry-After"] = "60" }
        end
        limited:makeRequestWithRetry("/user")
        local other, calls = API:new(settings("account-b")), 0
        function other:makeRequest() calls = calls + 1; return { result = true } end
        truthy(other:makeRequestWithRetry("/user"), "other token proceeds")
        equal(calls, 1, "request sent for the other token")
        equal(limited:makeRequestWithRetry("/user"), nil, "limited token still waits")
        API.clearRateLimit()
    end)

    test("calendar-invalid dates are rejected", function()
        for _, value in ipairs({ "2026-99-99", "2026-02-30", "2025-02-29", "2026-13", "2026-00-10", "2026-04-31" }) do
            equal(API.normalizeDateExpression(value), nil, value .. " rejected")
        end
        equal(API.normalizeDateExpression("2024-02-29"), "2024-02-29", "leap day")
        equal(API.normalizeDateExpression(">2026-10"), ">2026-10", "documented month form")
        equal(API.normalizeDateExpression("<2026-10-20"), "<2026-10-20", "documented day form")
        equal(API.normalizeDateExpression("2026"), "2026", "year form kept")
    end)

    test("a JSON error envelope from the cache endpoint is not saved as an article", function()
        API.clearRateLimit()
        local api = API:new(settings())
        function api:_performRequest()
            return '{"result":false,"errorMessage":"rejected"}', nil, 200, {}
        end
        local body, err = api:makeRequest("/raindrop/7/cache")
        equal(body, nil, "error envelope not returned as content")
        contains(err or "", "rejected", "server reason kept")
    end)

    test("403 explains the permission problem", function()
        local api = API:new(settings())
        function api:_performRequest()
            return '{"result":false,"errorMessage":"forbidden"}', nil, 403, {}
        end
        local _, err = api:makeRequest("/raindrop/7", "PUT", { important = true })
        contains(err, "permission", "permission explained")
        contains(err, "forbidden", "server detail kept")
    end)

    test("normal JSON has a default byte limit before parsing", function()
        local api = API:new(settings())
        local limit
        function api:_performRequest(_, _, _, _, _, options)
            limit = options.max_response_bytes
            return '{"ok":true}', nil, 200, { ["Content-Length"] = tostring(limit + 1) }
        end
        local result, err = api:makeRequest("/user")
        equal(result, nil, "declared overflow")
        equal(limit, 2 * 1024 * 1024, "default JSON limit")
        contains(err, "size limit")
    end)

    test("normal JSON streaming aborts an oversized body without Content-Length", function()
        local https = require("ssl.https")
        local original_request = https.request
        local config = settings()
        config.isTLSVerificationEnabled = function() return false end
        local api = API:new(config)
        local ok, err = pcall(function()
            https.request = function(request)
                equal(request.sink(string.rep("x", API.DEFAULT_JSON_RESPONSE_BYTES)), 1)
                local result, sink_error = request.sink("x")
                return result, sink_error
            end
            local result, request_error = api:makeRequest("/user")
            equal(result, nil)
            contains(request_error, "size limit")
        end)
        https.request = original_request
        if not ok then error(err, 0) end
    end)

    test("normal JSON gzip expansion uses the same default response bound", function()
        local compression = require("gota_compression")
        local original = compression.inflateGzipString
        local ok, err = pcall(function()
            compression.inflateGzipString = function(_, limit)
                equal(limit, API.DEFAULT_JSON_RESPONSE_BYTES, "decompressed JSON limit")
                return nil, "too large", true
            end
            local api = API:new(settings())
            function api:_performRequest()
                return "\31\139test", nil, 200, { ["Content-Encoding"] = "gzip" }
            end
            local result, request_error = api:makeRequest("/user")
            equal(result, nil)
            contains(request_error, "Decompressed response exceeds")
        end)
        compression.inflateGzipString = original
        if not ok then error(err, 0) end
    end)

    test("lost mutation response clears cache and never retries the write", function()
        local api = API:new(settings())
        api:_cacheResponse("/user", { result = true, user = {} })
        local calls = 0
        function api:makeRequest()
            calls = calls + 1
            return nil, "connection lost", nil, {}, true
        end
        local result, err = api:updateRaindrop(7, { important = true })
        equal(result, nil)
        equal(calls, 1, "write attempts")
        equal(next(api.response_cache), nil, "uncertain cache invalidated")
        contains(err, "server may have applied", "uncertain result guidance")
    end)

    test("executor wraps all read retries and returns cache data to the parent", function()
        local api = API:new(settings())
        local runs, calls = 0, 0
        function api:makeRequest()
            calls = calls + 1
            if calls == 1 then return nil, "temporary", 503 end
            return { result = true, user = { name = "reader" } }
        end
        api.sleep = function() end
        api:setRequestExecutor(function(task, context)
            runs = runs + 1
            equal(context.method, "GET")
            equal(context.endpoint, "/user")
            return task()
        end)
        equal(api:getUser().user.name, "reader")
        equal(api:getUser().user.name, "reader")
        equal(runs, 1, "executor calls")
        equal(calls, 2, "HTTP retries")
        truthy(api.transport_security_info, "child transport metadata")
    end)

    test("session changes during an operation discard its stale response", function()
        local config = settings()
        local api = API:new(config)
        api:setRequestExecutor(function()
            config:setToken("account-b")
            return { result = true, user = { name = "account-a" } }
        end)
        local result, err = api:getUser()
        equal(result, nil, "stale response")
        contains(err, "Account changed")
        equal(next(api.response_cache), nil, "stale result not cached")
    end)

    test("token validation uses a separate session without modifying saved credentials", function()
        local config = settings()
        local changes = 0
        config.setToken = function() changes = changes + 1 end
        local api = API:new(config)
        api:_cacheResponse("/user", { result = true, user = { name = "account-a" } })
        local original = API.makeRequest
        local ok, err = pcall(function()
            API.makeRequest = function(self)
                return { result = true, user = { name = self.settings:getToken() } }
            end
            local response = api:testToken("candidate")
            equal(response.user.name, "candidate", "candidate credential")
            equal(config:getToken(), "account-a", "active credential")
            equal(changes, 0, "shared token mutations")
            equal(api:getUser().user.name, "account-a", "live cache preserved")
        end)
        API.makeRequest = original
        if not ok then error(err, 0) end
    end)

    test("cancellation markers abort writes and token validation unchanged", function()
        local api = API:new(settings())
        api:_cacheResponse("/user", { result = true, user = {} })
        local marker = { gota_operation_cancelled = true }
        api:setRequestExecutor(function() error(marker, 0) end)
        local ok, err = pcall(function() api:updateRaindrop(7, { important = true }) end)
        equal(ok, false, "cancelled mutation")
        equal(err, marker, "mutation cancellation marker")
        equal(next(api.response_cache), nil, "uncertain cache cleared")
        ok, err = pcall(function() api:testToken("candidate") end)
        equal(ok, false, "cancelled token test")
        equal(err, marker, "token cancellation marker")
    end)

    test("TLS hostname matching rejects partial and multi-label wildcards", function()
        truthy(TLS.matchesDNSName("API.RAINDROP.IO", "api.raindrop.io"), "case insensitive")
        truthy(TLS.matchesDNSName("api.raindrop.io", "*.raindrop.io"), "one label wildcard")
        equal(TLS.matchesDNSName("a.b.raindrop.io", "*.raindrop.io"), false)
        equal(TLS.matchesDNSName("raindrop.io", "*.raindrop.io"), false)
        equal(TLS.matchesDNSName("api.raindrop.io", "a*.raindrop.io"), false)
        equal(TLS.matchesDNSName("example.com", "*.com"), false)
        equal(TLS.matchesDNSName("api.raindrop.io", "api.raindrop.io\0.attacker.test"), false)
        equal(TLS.matchesDNSName("api.raindrop.io", "api.raindrop.io.attacker.test"), false)
    end)

    test("TLS requires SAN and an explicit IP SAN for an IPv4 literal", function()
        local function certificate(san)
            return { extensions = function() return { ["2.5.29.17"] = san } end }
        end
        equal(TLS.certificateMatchesHost(certificate({}), "api.raindrop.io"), false)
        truthy(TLS.certificateMatchesHost(certificate({ dNSName = { "api.raindrop.io" } }),
            "api.raindrop.io"), "DNS SAN")
        equal(TLS.certificateMatchesHost(certificate({ dNSName = { "127.0.0.1" } }),
            "127.0.0.1"), false, "DNS SAN cannot authenticate IP")
        truthy(TLS.certificateMatchesHost(certificate({ iPAddress = { "127.0.0.1" } }),
            "127.0.0.1"), "IP SAN")
    end)

    local function withTransport(callback)
        local http, https = require("socket.http"), require("ssl.https")
        local old_request, old_tcp = http.request, https.tcp
        local fixture = "/tmp/gota_test_tls_ca.pem"
        local file = assert(io.open(fixture, "wb"))
        file:write("mock CA store\n")
        file:close()
        local ok, err = pcall(callback, http, https, fixture)
        http.request, https.tcp = old_request, old_tcp
        os.remove(fixture)
        if not ok then error(err, 0) end
    end

    test("secure TLS validates the hostname before HTTP sends any credentials", function()
        withTransport(function(http, https, fixture)
            local sent, closed = false, false
            local config = settings()
            config.getTLSCAFile = function() return fixture end
            local tls = TLS:new(config)
            https.tcp = function(parameters)
                equal(parameters.verify, "peer", "chain verification")
                equal(parameters.cafile, fixture, "CA store")
                return function()
                    return {
                        connect = function() return 1 end,
                        close = function() closed = true end,
                        getpeercertificate = function()
                            return { extensions = function()
                                return { ["2.5.29.17"] = { dNSName = { "attacker.test" } } }
                            end }
                        end,
                    }
                end
            end
            http.request = function(request)
                local connection = request.create()
                local ok, err = connection:connect("api.raindrop.io", 443)
                if not ok then return nil, err end
                sent = true
                return 1, 200
            end
            local result, err = tls:request({ url = "https://api.raindrop.io/", headers = {
                Authorization = "Bearer test-token",
            } })
            equal(result, nil)
            contains(err, "hostname")
            equal(sent, false, "HTTP did not begin")
            equal(closed, true, "rejected TLS connection closed")
            equal(tls:getSecurityInfo().validation_observed, false)
        end)
    end)

    test("secure TLS observes matching certificates and fails closed without a CA store", function()
        withTransport(function(http, https, fixture)
            local config = settings()
            config.getTLSCAFile = function() return fixture end
            local tls = TLS:new(config)
            https.tcp = function()
                return function()
                    return {
                        connect = function() return 1 end,
                        getpeercertificate = function()
                            return { extensions = function()
                                return { ["2.5.29.17"] = { dNSName = { "*.raindrop.io" } } }
                            end }
                        end,
                    }
                end
            end
            http.request = function(request)
                local result, err = request.create():connect("api.raindrop.io", 443)
                if not result then return nil, err end
                return 1, 200
            end
            equal(tls:request({ url = "https://api.raindrop.io/" }), 1)
            equal(tls:getSecurityInfo().validation_observed, true)
            config.getTLSCAFile = function() return fixture .. ".missing" end
            local result, err = tls:request({ url = "https://api.raindrop.io/" })
            equal(result, nil)
            contains(err, "certificate store")
        end)
    end)
end
