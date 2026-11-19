-- JWT 校验（依赖 lua-resty-jwt / resty.jwt）
return {
    name = "jwt-auth",
    priority = 850,
    schema = {
        secret = { type = "string", required = true },
        header = { type = "string", default = "Authorization" },
    },
    access = function(ctx, conf)
        local ok, jwt = pcall(require, "resty.jwt")
        if not ok then
            ngx.log(ngx.WARN, "[jwt-auth] resty.jwt not installed, skip verification")
            return nil
        end

        local auth = ngx.req.get_headers()[conf.header or "Authorization"] or ""
        local token = (string.match(auth, "^%s*[Bb]earer%s+(.+)$") or auth)

        local jwt_obj = jwt:verify(conf.secret, token)
        if not jwt_obj or not jwt_obj.verified then
            return { status = 401, blocked_by = "jwt-auth",
                     body = '{"code":40100,"message":"invalid or expired token"}' }
        end

        ctx.consumer = ctx.consumer or {}
        local p = jwt_obj.payload
        ctx.consumer.id = p and (p.sub or p.client_id)
    end,
}