-- =============================================================================
-- router.lua —— 动态路由匹配
-- 支持：prefix / 精确 uri 匹配、host 精确/通配、method 过滤、priority 排序
-- =============================================================================
local _M = {}

function _M.match(routes, host, uri, method)
    local sorted = {}
    for i, r in ipairs(routes or {}) do sorted[i] = r end
    table.sort(sorted, function(a, b) return (a.priority or 0) > (b.priority or 0) end)

    for _, r in ipairs(sorted) do
        if _M.match_one(r, host, uri, method) then
            return r
        end
    end
    return nil
end

function _M.match_one(r, host, uri, method)
    if r.enabled == false then return false end

    -- method 过滤
    if r.methods and #r.methods > 0 then
        local ok = false
        for _, m in ipairs(r.methods) do
            if m == method then ok = true break end
        end
        if not ok then return false end
    end

    -- host 匹配：精确 或 "*.example.com" 通配
    if r.host and r.host ~= "" and r.host ~= "*" then
        if not _M.host_match(r.host, host) then return false end
    end

    -- uri 匹配：prefix（uri 以 "/" 结尾或 match=prefix）或精确
    if r.uri and r.uri ~= "" then
        local is_prefix = (r.match == "prefix") or (string.sub(r.uri, -1) == "/")
        if is_prefix then
            if string.sub(uri, 1, #r.uri) ~= r.uri then return false end
        else
            if uri ~= r.uri then return false end
        end
    end

    return true
end

function _M.host_match(pattern, host)
    if string.sub(pattern, 1, 2) == "*." then
        local suffix = string.sub(pattern, 2)          -- 形如 ".example.com"
        if suffix == "" then return true end
        return string.sub(host, -#suffix) == suffix
    end
    return pattern == host
end

return _M