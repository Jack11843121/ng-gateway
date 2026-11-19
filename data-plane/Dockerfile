# NG 网关 · 数据面（OpenResty）运行时镜像
FROM openresty/openresty:1.25.3.1-4-jammy

# 可选 Lua 依赖（M1：jwt/etcd 未装时 jwt-auth/etcd 后端会自动跳过/报错）
#   opm get SkyLothar/lua-resty-jwt
#   opm get drmingdrmer/lua-resty-etcd  (或 luarocks install lua-resty-etcd)
WORKDIR /usr/local/ng-gateway
COPY nginx.conf ./
COPY conf ./conf/
COPY lua ./lua/
# 内置一份可运行的默认配置（生产用 volume 挂载覆盖 config.json）
RUN cp conf/config.example.json conf/config.json

EXPOSE 8080 9091
CMD ["/usr/local/openresty/bin/openresty", "-g", "daemon off;", "-p", "/usr/local/ng-gateway/", "-c", "nginx.conf"]