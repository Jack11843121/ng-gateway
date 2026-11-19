# NG 网关 · 数据面（OpenResty）

基于 **OpenResty（Nginx + LuaJIT）** 的网关引擎，动态路由 + 插件链，配置热更新无需 reload。

## 目录

```
nginx.conf                    # 引擎配置（数据面主入口 + /metrics 端点）
conf/config.example.json      # 配置示例（routes/upstreams/global_plugins）
lua/ng_gateway.lua            # 编排器：access → 插件链 + 路由 → balancer 选节点 → log 观测
lua/plugin.lua                # 插件框架（schema + priority + 阶段钩子）
lua/router.lua                # 动态路由匹配（prefix/精确 + host 通配 + method）
lua/config_store.lua          # 配置加载（file 默认，etcd 预留）
lua/plugins/*.lua             # 内置插件
```

## 运行前提

- OpenResty ≥ 1.21（自带 `lua-cjson`、`lua-resty-core`）
- 可选：`lua-resty-jwt`（启用 jwt-auth）、`lua-resty-etcd`（启用 etcd 后端）

## 快速部署

```bash
# 1) 安装 OpenResty（CentOS/Ubuntu 见 openresty.org）
# 2) 将本目录部署为 /usr/local/ng-gateway/
sudo mkdir -p /usr/local/ng-gateway
sudo cp -r . /usr/local/ng-gateway/
# 3) 准备配置
sudo cp conf/config.example.json conf/config.json   # 改成你的 routes/upstreams
# 4) 启动
sudo /usr/local/openresty/nginx/sbin/nginx -p /usr/local/ng-gateway/ -c nginx.conf
```

## 本地演示（先起一个 mock 上游）

```bash
# 上游 demo 监听 18080（对应 config.example.json 里的节点）
python3 -m http.server 18080
curl http://127.0.0.1:8080/orders/123 -H 'X-Api-Key: demo-secret-key'
curl http://127.0.0.1:9091/metrics
```

## 内置插件

| 插件 | 说明 |
| --- | --- |
| request-id | 读入/生成 X-Request-Id 并透传 |
| api-key | 请求头/query 的 API Key 白名单 |
| jwt-auth | Bearer JWT 校验（依赖 lua-resty-jwt） |
| rate-limit | 固定窗口限流（count/window，key=ip|consumer） |
| ip-blacklist | 精确 IP + IPv4 CIDR 黑名单 |
| waf | 自研轻量规则（SQLi/XSS/路径穿越/命令注入） |
| observability | 指标打点 + JSON 访问日志 + /metrics 输出 |

## 配置格式

见 `conf/config.example.json`：`routes[]`（含 `plugins[]`）、`upstreams[]`（含 `nodes[]`、`health_check`）、`global_plugins[]`。
控制面（control-plane）维护并下发同一份 JSON（或 etcd 的 `/ng/gateway/config`）。