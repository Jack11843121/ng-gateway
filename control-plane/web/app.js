// NG 网关 管理控制台（Vue3，无构建，同源调用 Admin API）
const { createApp } = Vue

createApp({
  data() {
    return {
      health: '连接中…',
      upstreams: [],
      routes: [],
      config: {},
      error: '',
      upForm: { id: '', name: '', nodes: '' },
      rtForm: { id: '', name: '', uri: '', upstream_id: '' },
    }
  },
  computed: {
    configJson() {
      return JSON.stringify(this.config, null, 2)
    },
  },
  methods: {
    async api(path, opts = {}) {
      const r = await fetch('/api/v1' + path, {
        headers: { 'Content-Type': 'application/json' },
        ...opts,
      })
      return r.json()
    },
    async load() {
      try {
        const [ups, rts, cfg] = await Promise.all([
          this.api('/upstreams'),
          this.api('/routes'),
          this.api('/config'),
        ])
        this.upstreams = (ups && ups.data) || []
        this.routes = (rts && rts.data) || []
        this.config = (cfg && cfg.data) || {}
        this.health = '已连接'
        this.error = ''
      } catch (e) {
        this.health = '连接失败'
        this.error = '无法连接控制面：' + (e && e.message)
      }
    },
    async addUpstream() {
      try {
        const nodes = this.upForm.nodes.split(',').map((s) => {
          const [host, port] = s.trim().split(':')
          return { host, port: parseInt(port, 10), weight: 1 }
        })
        await this.api('/upstreams', {
          method: 'POST',
          body: JSON.stringify({ id: this.upForm.id, name: this.upForm.name || this.upForm.id, scheme: 'http', lb: 'round_robin', nodes }),
        })
        this.upForm = { id: '', name: '', nodes: '' }
        await this.load()
      } catch (e) { this.error = '添加上游失败：' + (e && e.message) }
    },
    async addRoute() {
      try {
        await this.api('/routes', {
          method: 'POST',
          body: JSON.stringify({
            id: this.rtForm.id, name: this.rtForm.name || this.rtForm.id, uri: this.rtForm.uri,
            match: 'prefix', upstream_id: this.rtForm.upstream_id, enabled: true, plugins: [],
          }),
        })
        this.rtForm = { id: '', name: '', uri: '', upstream_id: '' }
        await this.load()
      } catch (e) { this.error = '添加路由失败：' + (e && e.message) }
    },
    async delRoute(id) {
      try {
        await fetch('/api/v1/routes/' + encodeURIComponent(id), { method: 'DELETE' })
        await this.load()
      } catch (e) { this.error = '删除失败：' + (e && e.message) }
    },
  },
  mounted() {
    this.load()
  },
}).mount('#app')