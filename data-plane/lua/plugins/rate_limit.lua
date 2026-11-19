-- 限流（M1：固定窗口，基于共享字典计数；algorithm 参数预留滑窗/令牌桶）
return {
    name = "rate-limit",
    priority = 800,
    schema = {
        count     = { type = "integer", required = true },
        window    = { type = "integer", default = 60 },
        key       = { type = "string",  default = "ip" },  -- ip | consumer
        algorithm = { type = "string",  default = "sliding" },
    },
    access = function(ctx, conf)
        local key
        if conf.key == "consumer" and ctx.consumer and ctx.consumer.id then
            key = "consumer:" .. ctx.consumer.id
        else
            key = "ip:" .. ngx.var.remote_addr
        end

        local dk = "rl:" .. tostring(ctx.route and ctx.route.id or "x") .. ":" .. key
        local d = ngx.shared.ng_counters

        -- 固定窗口：首次创建时值=1 并设 TTL=window；其后自增
        local window = tonumber(conf.window) or 60
        local cur, err = d:incr(dk, 1, 1, window)
        if not cur then
            return { status = 500, blocked_by = "rate-limit",
                     body = '{"code":50000,"message":"rate limit store error: ' .. tostring(err) .. '"}' }
        end

        local limit = tonumber(conf.count)
        if cur > limit then
            ngx.header["X-RateLimit-Limit"] = tostring(limit)
            ngx.header["X-RateLimit-Remaining"] = "0"
            ngx.header["X-RateLimit-Reset"] = tostring(ngx.time() + window)
            return { status = 429, blocked_by = "rate-limit",
                     body = '{"code":42900,"message":"rate limited"}' }
        end
    end,
}