-- 自研 Lua WAF（M1 轻量规则集：SQLi / XSS / 路径穿越 / 命令注入）
-- mode=block 拦截；mode=log 仅记录不拦截。完整规则集按 OWASP CRS 逐步补充。
local RULES = {
    { id = 1001, name = "sql-injection",   p = [[(\bselect\b.{0,20}\bfrom\b)|(\bunion\b.{0,20}\bselect\b)|(''.{0,20}or.{0,20}'')|(--)]] },
    { id = 1002, name = "xss",             p = [[(<script)|(<img[^>]+onerror)|(javascript:)|(onerror\s*=)|(onload\s*=)]] },
    { id = 1003, name = "path-traversal",  p = [[(\.\./)|(%2e%2e%2f)|(\.\.%5c)|(\.\.\\\\)]] },
    { id = 1004, name = "command-inject",  p = [[(;\s*(cat|ls|rm|wget|curl|sh|bash)\b)|(\|{1,2}\s*(cat|ls|whoami)\b)]] },
}

return {
    name = "waf",
    priority = 650,
    schema = {
        mode = { type = "string", default = "block" },  -- block | log
    },
    access = function(ctx, conf)
        local mode = conf.mode or "block"
        -- M1 只检查 URI + query + User-Agent
        local uri = ngx.var.request_uri or ""
        local ua  = ngx.var.http_user_agent or ""
        local ref = ngx.var.http_referer or ""
        local target = uri .. "\n" .. ua .. "\n" .. ref

        for _, rule in ipairs(RULES) do
            local from, to = ngx.re.find(target, rule.p, "joi")
            if from then
                ngx.log(ngx.WARN, "[waf] hit rule ", rule.id, " ", rule.name)
                if mode == "block" then
                    return { status = 403, blocked_by = "waf",
                             body = '{"code":40300,"message":"waf blocked: ' .. rule.name .. '"}' }
                end
            end
        end
    end,
}