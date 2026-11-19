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

-- etcd 后端（M1 预留）：
--   期望用 lua-resty-etcd 读取 /ng/gateway/config 并 watch；
--   落地步骤见数据面 README。
function _M.load_from_etcd()
    local ok, etcd = pcall(require, "resty.etcd")
    if not ok then
        return nil, "etcd backend requires lua-resty-etcd"
    end
    -- 示例（伪代码，需按 lua-resty-etcd API 细化）：
    -- local cli = etcd.new { protocol = "v3", http_host = "http://127.0.0.1:2379" }
    -- local res = cli:get("/ng/gateway/config")
    -- return _M.normalize(cjson.decode(res))
    return nil, "etcd backend not fully wired yet"
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