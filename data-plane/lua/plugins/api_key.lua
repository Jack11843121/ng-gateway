-- API Key 校验：从请求头或 query 中取 key，命中 keys 白名单即放行
return {
    name = "api-key",
    priority = 900,
    schema = {
        keys   = { type = "array" },
        header = { type = "string", default = "X-Api-Key" },
        query  = { type = "string", default = "apikey" },
    },
    access = function(ctx, conf)
        local keys = conf.keys or {}
        if #keys == 0 then return nil end   -- 未配置 keys 视为放行

        local h = ngx.req.get_headers()
        local key = h[conf.header or "X-Api-Key"]
        if not key or key == "" then
            key = ngx.var["arg_" .. (conf.query or "apikey")]
        end

        for _, k in ipairs(keys) do
            if k == key then
                ctx.consumer = ctx.consumer or {}
                ctx.consumer.key = key
                return nil
            end
        end

        return { status = 401, blocked_by = "api-key",
                 body = '{"code":40100,"message":"invalid api key"}' }
    end,
}