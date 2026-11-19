// Package store 提供配置存储抽象：默认内存存储，可选 etcd（通过环境变量 ETCD_ENDPOINTS 开启）。
package store

import (
	"context"
	"encoding/json"
	"errors"
	"os"
	"strings"
	"sync"
	"time"

	clientv3 "go.etcd.io/etcd/client/v3"
)

// GatewayConfig 与数据面 config.json 同构，控制面维护并下发给数据面。
type GatewayConfig struct {
	Version       int              `json:"version"`
	GlobalPlugins []PluginBinding  `json:"global_plugins"`
	Routes        []Route          `json:"routes"`
	Upstreams     []Upstream       `json:"upstreams"`
}

type PluginBinding struct {
	Type   string         `json:"type"`
	Config map[string]any `json:"config,omitempty"`
}

type Route struct {
	ID         string          `json:"id"`
	Name       string          `json:"name"`
	URI        string          `json:"uri"`
	Match      string          `json:"match"`
	Host       string          `json:"host,omitempty"`
	Methods    []string        `json:"methods,omitempty"`
	Priority   int             `json:"priority"`
	UpstreamID string          `json:"upstream_id"`
	Plugins    []PluginBinding `json:"plugins,omitempty"`
	Enabled    bool            `json:"enabled"`
}

type Upstream struct {
	ID     string `json:"id"`
	Name   string `json:"name"`
	Scheme string `json:"scheme"`
	LB     string `json:"lb"`
	Nodes  []Node `json:"nodes"`
}

type Node struct {
	Host   string `json:"host"`
	Port   int    `json:"port"`
	Weight int    `json:"weight"`
}

// Store 抽象控制面的配置读写。
type Store interface {
	Save(cfg *GatewayConfig) error
	Load() (*GatewayConfig, error)
	Close() error
}

// Memory 兜底存储（本地 kv，单进程）。
type memoryStore struct {
	mu  sync.RWMutex
	cfg *GatewayConfig
}

func (m *memoryStore) Save(cfg *GatewayConfig) error {
	m.mu.Lock()
	defer m.mu.Unlock()
	cp := *cfg
	cp.Version++
	m.cfg = &cp
	return nil
}

func (m *memoryStore) Load() (*GatewayConfig, error) {
	m.mu.RLock()
	defer m.mu.RUnlock()
	if m.cfg == nil {
		return &GatewayConfig{Version: 1, Routes: []Route{}, Upstreams: []Upstream{}}, nil
	}
	cp := *m.cfg
	return &cp, nil
}

func (m *memoryStore) Close() error { return nil }

// etcdStore 将整个配置文档读写到 /ng/gateway/config（供数据面 watch/读取）。
type etcdStore struct {
	cli  *clientv3.Client
	key  string
}

func (e *etcdStore) Save(cfg *GatewayConfig) error {
	b, err := json.Marshal(cfg)
	if err != nil {
		return err
	}
	ctx, cancel := context.WithTimeout(context.Background(), 3*time.Second)
	defer cancel()
	_, err = e.cli.Put(ctx, e.key, string(b))
	return err
}

func (e *etcdStore) Load() (*GatewayConfig, error) {
	ctx, cancel := context.WithTimeout(context.Background(), 3*time.Second)
	defer cancel()
	resp, err := e.cli.Get(ctx, e.key)
	if err != nil {
		return nil, err
	}
	if len(resp.Kvs) == 0 {
		return &GatewayConfig{Version: 1, Routes: []Route{}, Upstreams: []Upstream{}}, nil
	}
	var cfg GatewayConfig
	if err := json.Unmarshal(resp.Kvs[0].Value, &cfg); err != nil {
		return nil, err
	}
	return &cfg, nil
}

func (e *etcdStore) Close() error { return e.cli.Close() }

// New 根据环境变量选择存储后端：
//   ETCD_ENDPOINTS=127.0.0.1:2379 → etcd；否则 → memory。
func New() (Store, error) {
	ep := os.Getenv("ETCD_ENDPOINTS")
	if strings.TrimSpace(ep) == "" {
		return &memoryStore{}, nil
	}
	cli, err := clientv3.New(clientv3.Config{
		Endpoints:   strings.Split(ep, ","),
		DialTimeout: 3 * time.Second,
	})
	if err != nil {
		return nil, err
	}
	return &etcdStore{cli: cli, key: "/ng/gateway/config"}, nil
}

var ErrNotFound = errors.New("not found")