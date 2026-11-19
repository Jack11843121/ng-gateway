-- =============================================================================
-- plugin.lua —— NG 网关插件框架
-- 每个插件是一个 Lua 模块：{ name, priority, schema, 以及可选阶段钩子 }
-- 阶段钩子：rewrite / access / header_filter / body_filter / log
-- 钩子返回 nil 表示放行；返回 { status=..., body=... } 表示短路并响应。
-- =============================================================================
local _M = { _registry = {} }

-- 注册插件（返回插件表，便于 require 后直接 return plugin.register({...})）
function _M.register(p)
    assert(type(p.name) == "string" and p.name ~= "", "plugin.name required")
    p.priority = p.priority or 1000
    p.schema = p.schema or {}
    p.version = p.version or "0.1.0"
    _M._registry[p.name] = p
    return p
end

function _M.get(name)
    return _M._registry[name]
end

function _M.names()
    local t = {}
    for k, _ in pairs(_M._registry) do table.insert(t, k) end
    table.sort(t)
    return t
end

-- 轻量 schema 校验：只检查 required 字段是否存在（M1 版本）
function _M.validate(p, conf)
    conf = conf or {}
    for k, def in pairs(p.schema or {}) do
        if def.required and conf[k] == nil then
            return false, ("plugin[%s] missing required field: %s"):format(p.name, k)
        end
    end
    return true
end

-- 组装插件链：bindings = [{type=..., config=...}, ...] → 按 priority 升序
function _M.assemble(bindings)
    local chain = {}
    for _, b in ipairs(bindings or {}) do
        local p = _M.get(b.type)
        if p then
            table.insert(chain, { mod = p, conf = b.config or b.conf or {} })
        else
            ngx.log(ngx.WARN, "[plugin] unknown plugin type: ", tostring(b.type))
        end
    end
    table.sort(chain, function(a, b) return a.mod.priority < b.mod.priority end)
    return chain
end

-- 执行某阶段的钩子链；返回第一个非 nil 的错误（含 err.status 断路）
function _M.run(phase, chain, ctx)
    for _, item in ipairs(chain) do
        local fn = item.mod[phase]
        if fn then
            local ok, res = pcall(fn, ctx, item.conf)
            if not ok then
                ngx.log(ngx.ERR, "[plugin][", item.mod.name, "][", phase, "] error: ", tostring(res))
                return { status = 500, body = '{"code":50000,"message":"plugin internal error"}' }
            end
            if res ~= nil then
                return res
            end
        end
    end
    return nil
end

return _M