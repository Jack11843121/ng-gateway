-- IP 黑名单（精确 IP + IPv4 CIDR）
local bit = require "bit"

local function ip_to_num(ip)
    local a, b, c, d = ip:match("^(%d+)%.(%d+)%.(%d+)%.(%d+)$")
    if not a then return nil end
    return ((tonumber(a) * 16777216) + (tonumber(b) * 65536) + (tonumber(c) * 256) + tonumber(d))
end

local function cidr_match(cidr, ip)
    local pfx, bits = cidr:match("^([%d%.]+)/(%d+)$")
    if not pfx then return false end
    local ipn, pn = ip_to_num(ip), ip_to_num(pfx)
    if not ipn or not pn then return false end
    bits = tonumber(bits) or 32
    if bits >= 32 then return ipn == pn end
    local mask = 0xffffffff - (2 ^ (32 - bits) - 1)
    return bit.band(ipn, mask) == bit.band(pn, mask)
end

return {
    name = "ip-blacklist",
    priority = 700,
    schema = {
        ips   = { type = "array" },   -- 精确 IP
        cidrs = { type = "array" },   -- CIDR
    },
    access = function(ctx, conf)
        local ip = ngx.var.remote_addr

        for _, v in ipairs(conf.ips or {}) do
            if v == ip then
                return { status = 403, blocked_by = "ip-blacklist",
                         body = '{"code":40300,"message":"forbidden"}' }
            end
        end

        for _, c in ipairs(conf.cidrs or {}) do
            if cidr_match(c, ip) then
                return { status = 403, blocked_by = "ip-blacklist",
                         body = '{"code":40300,"message":"forbidden"}' }
            end
        end
    end,
}