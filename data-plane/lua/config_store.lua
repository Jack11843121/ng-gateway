-- =============================================================================
-- config_store.lua —— 配置加载
-- 后端可选：file（本地 JSON，默认）/ etcd（预留，需 lua-resty-etcd）
-- 通过环境变量切换：NG_CONFIG_BACKEND=file|etcd  NG_GATEWAY_CONFIG=/path/config.json
-- =============================================================================
local _M = {}
local cjson = require "cjson.safe"

local CONFIG_PATH = os.getenv("NG_GATEWAY_CONFIG") or "/usr/local/ng-gateway/conf/config.json"

function _M.load()
    local backend = os.getenv("NG_CONFIG_BACKEND") or "file"
    if backend == "etcd" then
        return _M.load_from_etcd()
    end
    return _M.load_from_file()
end

function _M.load_from_file()
    local f, err = io.open(CONFIG_PATH, "rb")
    if not f then
        return nil, "open config failed: " .. tostring(err)
    end
    local data = f:read("*a")
    f:close()
    local cfg = cjson.decode(data)
    if not cfg then
        return nil, "invalid config json"
    end
    return _M.normalize(cfg)
end

-- etcd 后端：读取控制面写入的 /ng/gateway/config（JSON），并定时刷新（M1 用轮询，后续可切 watch）
function _M.load_from_etcd()
    local ok, etcd = pcall(require, "resty.etcd")
    if not ok then
        return nil, "etcd backend requires lua-resty-etcd (drmingdrmer/lua-resty-etcd)"
    end

    local host = os.getenv("ETCD_ENDPOINTS") or "http://127.0.0.1:2379"
    local client, err = etcd.new({
        protocol = "v3",
        http_host = { host },
        api_prefix = "/v3",
        serializer = "cjson",
    })
    if err then
        return nil, "etcd connect: " .. tostring(err)
    end

    local res, gerr = client:get("/ng/gateway/config")
    if gerr then
        return nil, "etcd get: " .. tostring(gerr)
    end

    -- lua-resty-etcd v3 返回 { {key=..., value=...}, ... }（value 默认 base64）
    local value
    if type(res) == "table" and res[1] then
        value = res[1].value or res[1][2]
    elseif type(res) == "string" then
        value = res
    end
    if value == nil then
        return nil, "etcd: config key empty"
    end

    local raw = value
    if type(value) == "string" then
        local dec = ngx.decode_base64(value)
        if dec then raw = dec end
    end

    local cfg = cjson.decode(raw)
    if not cfg then
        return nil, "etcd: config not valid json"
    end
    return _M.normalize(cfg)
end

function _M.normalize(cfg)
    -- 建立 upstream 按 id 索引，加速查找
    cfg.upstreams_map = {}
    for _, up in ipairs(cfg.upstreams or {}) do
        cfg.upstreams_map[up.id] = up
    end
    return cfg
end

return _M