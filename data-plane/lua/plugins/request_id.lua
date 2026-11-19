-- 请求 ID：读入或生成 X-Request-Id，传给上游并写入上下文
return {
    name = "request-id",
    priority = 1000,
    schema = {
        header = { type = "string", default = "X-Request-Id" },
    },
    access = function(ctx, conf)
        local header = (conf and conf.header) or "X-Request-Id"
        local h = ngx.req.get_headers()
        local id = h[header]
        if not id or id == "" then
            id = ngx.var.request_id or ("ng" .. tostring(ngx.now() * 1000))
        end
        ngx.req.set_header(header, id)   -- 透传/回写，供上游与日志使用
        ctx.request_id = id
    end,
}