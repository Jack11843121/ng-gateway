-- 观测：请求计数/状态码/路由维度打点 + 结构化访问日志 + Prometheus /metrics 输出
local _M = {
    name = "observability",
    priority = 100000,   -- 排在最后，事后打点
}

-- 打点（log 阶段调用）
function _M.log(ctx)
    local d = ngx.shared.ng_metrics
    if not d then return end
    d:incr("http_requests_total", 1, 0)
    local status = tostring(ctx and ctx.status or ngx.status or "0")
    d:incr("http_status_" .. status, 1, 0)
    if ctx and ctx.route and ctx.route.id then
        d:incr("route_hits_" .. ctx.route.id, 1, 0)
    end
    if ctx and ctx.latency_ms then
        d:incr("latency_bucket_" .. tostring(math.floor((ctx.latency_ms / 10) * 10)), 1, 0)
    end

    -- 结构化访问日志（JSON）
    ngx.log(ngx.INFO, string.format(
        '{"t":"access","request_id":"%s","host":"%s","uri":"%s","method":"%s",' ..
        '"route":"%s","status":%s,"latency_ms":%d,"remote_addr":"%s"}',
        (ctx and ctx.request_id) or "-",
        (ctx and ctx.host) or "-",
        (ctx and ctx.uri) or ngx.var.uri,
        (ctx and ctx.method) or "-",
        (ctx and ctx.route and ctx.route.name) or "-",
        status,
        (ctx and math.floor(ctx.latency_ms or 0)) or 0,
        ngx.var.remote_addr))
end

-- 输出 Prometheus 文本
function _M.render()
    ngx.header["Content-Type"] = "text/plain; version=0.0.4"
    local d = ngx.shared.ng_metrics
    local keys = d and d:get_keys(0) or {}
    local out = {}
    local function emit(name, val)
        if val then table.insert(out, name .. " " .. tostring(val)) end
    end
    for _, k in ipairs(keys) do
        local v = d:get(k)
        if k == "http_requests_total" then
            emit("ng_gateway_http_requests_total", v)
        elseif string.sub(k, 1, 12) == "http_status_" then
            emit('ng_gateway_http_status_total{status="' .. string.sub(k, 13) .. '"}', v)
        elseif string.sub(k, 1, 11) == "route_hits_" then
            emit('ng_gateway_route_hits_total{route="' .. string.sub(k, 12) .. '"}', v)
        elseif string.sub(k, 1, 15) == "latency_bucket_" then
            emit('ng_gateway_latency_bucket{le="' .. string.sub(k, 16) .. '"}', v)
        end
    end
    ngx.print(table.concat(out, "\n") .. "\n")
end

return _M