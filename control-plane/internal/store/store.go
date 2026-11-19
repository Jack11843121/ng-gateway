// Package store 提供配置存储抽象。
// M1：仅内存存储（纯标准库，保证可编译可运行）。etcd 后端将在 M2 接入
//（届时在可运行 Go 的环境执行 go mod tidy 生成 go.sum，再引入 go.etcd.io/etcd/client/v3）。
package store

import (
	"errors"
	"sync"
)

// GatewayConfig 与数据面 config.json 同构，控制面维护并下发给数据面。
type GatewayConfig struct {
	Version       int             `json:"version"`
	GlobalPlugins []PluginBinding `json:"global_plugins"`
	Routes        []Route         `json:"routes"`
	Upstreams     []Upstream      `json:"upstreams"`
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

// memoryStore（M1 默认）：进程内存储。
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

// New 返回存储后端；M1 仅有内存实现，M2 按 ETCD_ENDPOINTS 环境变量接 etcd。
func New() (Store, error) {
	return &memoryStore{}, nil
}

var ErrNotFound = errors.New("not found")