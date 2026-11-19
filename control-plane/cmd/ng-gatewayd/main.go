// ng-gatewayd —— NG 网关管理端（控制面）入口
// 负责 route/upstream/global_plugins 的配置管理，并通过 store（etcd/memory）下发给数据面。
// 数据面（OpenResty）读取同一份配置文档（见 data-plane/conf/config.example.json）。
package main

import (
	"encoding/json"
	"flag"
	"log"
	"net/http"
	"strings"

	"github.com/Jack11843121/ng-gateway/control-plane/internal/store"
)

var st store.Store

func write(w http.ResponseWriter, code int, v any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(code)
	_ = json.NewEncoder(w).Encode(map[string]any{"code": code, "data": v})
}

func writeErr(w http.ResponseWriter, code int, msg string) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(code)
	_ = json.NewEncoder(w).Encode(map[string]any{"code": code, "message": msg})
}

func healthz(w http.ResponseWriter, _ *http.Request) {
	write(w, 200, map[string]any{"status": "ok", "service": "ng-gatewayd"})
}

// GET /api/v1/routes    列出全部路由
// POST /api/v1/routes   新增路由
func routesHandler(w http.ResponseWriter, r *http.Request) {
	cfg, err := st.Load()
	if err != nil {
		writeErr(w, 500, "load config: "+err.Error())
		return
	}

	switch r.Method {
	case http.MethodGet:
		write(w, 200, cfg.Routes)
	case http.MethodPost:
		var rt store.Route
		if err := json.NewDecoder(r.Body).Decode(&rt); err != nil {
			writeErr(w, 400, "bad route json: "+err.Error())
			return
		}
		if strings.TrimSpace(rt.ID) == "" {
			writeErr(w, 400, "route.id is required")
			return
		}
		cfg.Routes = append(cfg.Routes, rt)
		if err := st.Save(cfg); err != nil {
			writeErr(w, 500, "save config: "+err.Error())
			return
		}
		write(w, 200, rt)
	default:
		writeErr(w, 405, "method not allowed")
	}
}

// DELETE /api/v1/routes/{id}
func routeOneHandler(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodDelete {
		writeErr(w, 405, "method not allowed")
		return
	}
	id := strings.TrimPrefix(r.URL.Path, "/api/v1/routes/")
	cfg, err := st.Load()
	if err != nil {
		writeErr(w, 500, "load config: "+err.Error())
		return
	}
	out := cfg.Routes[:0]
	found := false
	for _, rt := range cfg.Routes {
		if rt.ID == id {
			found = true
			continue
		}
		out = append(out, rt)
	}
	if !found {
		writeErr(w, 404, "route not found")
		return
	}
	cfg.Routes = out
	if err := st.Save(cfg); err != nil {
		writeErr(w, 500, "save config: "+err.Error())
		return
	}
	write(w, 200, map[string]any{"deleted": id})
}

// GET /api/v1/upstreams     列出全部上游
// POST /api/v1/upstreams    新增上游
func upstreamsHandler(w http.ResponseWriter, r *http.Request) {
	cfg, err := st.Load()
	if err != nil {
		writeErr(w, 500, "load config: "+err.Error())
		return
	}
	switch r.Method {
	case http.MethodGet:
		write(w, 200, cfg.Upstreams)
	case http.MethodPost:
		var up store.Upstream
		if err := json.NewDecoder(r.Body).Decode(&up); err != nil {
			writeErr(w, 400, "bad upstream json: "+err.Error())
			return
		}
		if strings.TrimSpace(up.ID) == "" {
			writeErr(w, 400, "upstream.id is required")
			return
		}
		cfg.Upstreams = append(cfg.Upstreams, up)
		if err := st.Save(cfg); err != nil {
			writeErr(w, 500, "save config: "+err.Error())
			return
		}
		write(w, 200, up)
	default:
		writeErr(w, 405, "method not allowed")
	}
}

// GET /api/v1/config   返回完整配置（与数据面 config.json 同构）
func configHandler(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		writeErr(w, 405, "method not allowed")
		return
	}
	cfg, err := st.Load()
	if err != nil {
		writeErr(w, 500, "load config: "+err.Error())
		return
	}
	write(w, 200, cfg)
}

func main() {
	addr := flag.String("addr", ":8081", "admin API listen address")
	flag.Parse()

	var err error
	st, err = store.New()
	if err != nil {
		log.Fatalf("init store: %v", err)
	}
	defer st.Close()

	mux := http.NewServeMux()
	mux.HandleFunc("/healthz", healthz)
	mux.HandleFunc("/api/v1/routes", routesHandler)
	mux.HandleFunc("/api/v1/routes/", routeOneHandler)
	mux.HandleFunc("/api/v1/upstreams", upstreamsHandler)
	mux.HandleFunc("/api/v1/config", configHandler)

	log.Printf("ng-gatewayd admin listening on %s", *addr)
	if err := http.ListenAndServe(*addr, mux); err != nil {
		log.Fatalf("http server: %v", err)
	}
}