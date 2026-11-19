-- =============================================================================
-- ng_gateway.lua —— 数据面编排器（bootstrap）
-- init(插件注册) → init_worker(加载配置+定时刷新) → access(插件链+路由) → balancer(选节点) → log(观测)
-- =============================================================================
local cjson = require "cjson.safe"
local plugin = require "plugin"
local router = require "router"
local config_store = require "config_store"

local _M = {}

function _M.init()
    -- 注册内置插件
    plugin.register(require "plugins.request_id")
    plugin.register(require "plugins.api_key")
    plugin.register(require "plugins.jwt_auth")
    plugin.register(require "plugins.rate_limit")
    plugin.register(require "plugins.ip_blacklist")
    plugin.register(require "plugins.waf")
    plugin.register(require "plugins.observability")
    ngx.log(ngx.INFO, "[ng-gateway] plugins loaded: ", table.concat(plugin.names(), ","))
end

function _M.init_worker()
    _M.reload()
    -- 定时刷新配置（file 后端轮询；etcd 后端后续改为 watch）
    local ok, err = ngx.timer.every(10, function(premature)
        if not premature then _M.reload() end
    end)
    if not ok then
        ngx.log(ngx.ERR, "[ng-gateway] refresh timer failed: ", tostring(err))
    end
end

function _M.reload()
    local cfg, err = config_store.load()
    if not cfg then
        ngx.log(ngx.ERR, "[ng-gateway] config load failed: ", tostring(err))
        return false
    end
    local ok, serr = ngx.shared.ng_router:set("cfg", cjson.encode(cfg))
    if not ok then
        ngx.log(ngx.ERR, "[ng-gateway] store cfg failed: ", tostring(serr))
        return false
    end
    ngx.log(ngx.INFO, "[ng-gateway] config reloaded, routes=", #(cfg.routes or {}),
            ", upstreams=", #(cfg.upstreams or {}))
    return true
end

function _M.config()
    local raw = ngx.shared.ng_router:get("cfg")
    if not raw then
        _M.reload()
        raw = ngx.shared.ng_router:get("cfg")
    end
    return raw and cjson.decode(raw) or nil
end

function _M.access()
    local cfg = _M.config()
    if not cfg then
        ngx.status = 503
        ngx.header["Content-Type"] = "application/json"
        ngx.say('{"code":50300,"message":"gateway config not ready"}')
        return ngx.exit(503)
    end

    local host   = ngx.var.host
    local uri    = ngx.var.uri
    local method = ngx.req.get_method()

    local route = router.match(cfg.routes, host, uri, method)
    if not route then
        ngx.status = 404
        ngx.header["Content-Type"] = "application/json"
        ngx.say('{"code":40400,"message":"no route matched"}')
        return ngx.exit(404)
    end

    local up = cfg.upstreams_map and cfg.upstreams_map[route.upstream_id]
    if not up or not up.nodes or #up.nodes == 0 then
        ngx.status = 502
        ngx.header["Content-Type"] = "application/json"
        ngx.say('{"code":50200,"message":"no available upstream"}')
        return ngx.exit(502)
    end

    local ctx = {
        cfg = cfg, route = route, upstream = up,
        host = host, uri = uri, method = method,
        started_at = ngx.now(),
    }

    -- 组装插件链：全局插件 + 路由插件
    local bindings = {}
    for _, g in ipairs(cfg.global_plugins or {}) do
        table.insert(bindings, { type = g.type, config = g.config or {} })
    end
    for _, p in ipairs(route.plugins or {}) do
        table.insert(bindings, { type = p.type, config = p.config or p.conf or {} })
    end
    ctx.chain = plugin.assemble(bindings)

    local err = plugin.run("access", ctx.chain, ctx)
    if err then
        ngx.status = err.status and tonumber(err.status) or 500
        ngx.header["Content-Type"] = "application/json"
        ngx.say(err.body or ('{"code":' .. ngx.status .. ',"message":"blocked"}'))
        return ngx.exit(ngx.status)
    end

    ngx.ctx.ng_ctx = ctx
end

function _M.balancer()
    local ctx = ngx.ctx.ng_ctx
    if not ctx or not ctx.upstream then
        return ngx.exit(502)
    end
    local node = _M.select_node(ctx.upstream)
    if not node then
        ngx.log(ngx.ERR, "[ng-gateway] no upstream node")
        return ngx.exit(502)
    end
    local ok, err = ngx.balancer.set_current_peer(node.host, node.port)
    if not ok then
        ngx.log(ngx.ERR, "[ng-gateway] set_current_peer failed: ", tostring(err))
        return ngx.exit(502)
    end
end

function _M.log()
    local ctx = ngx.ctx.ng_ctx
    if not ctx then return end
    ctx.status = ngx.status
    ctx.latency_ms = (ngx.now() - ctx.started_at) * 1000
    if ctx.chain then
        plugin.run("log", ctx.chain, ctx)
    end
end

function _M.metrics()
    local obs = plugin.get("observability")
    if obs and obs.render then
        obs.render()
    else
        ngx.header["Content-Type"] = "text/plain; version=0.0.4"
        ngx.say("# ng-gateway metrics")
    end
end

-- 简单轮询负载均衡（M1；后续支持权重/least_conn/一致性哈希）
function _M.select_node(up)
    local nodes = up.nodes
    local n = #nodes
    if n == 0 then return nil end
    if n == 1 then return nodes[1] end
    local k = "rr:" .. tostring(up.id or "x")
    local idx = ngx.shared.ng_counters:incr(k, 1, 0) or 1
    return nodes[((idx - 1) % n) + 1]
end

return _M