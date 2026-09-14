// OpenRouter への Authorization をエージェントから隔離するためのブローカー。
//
// 実装 handler は、信頼できない入力（GitHub issue の本文）を読んだエージェントに
// Bash を持たせて任意のコードを実行させる。そのエージェントの環境に API キーの実値が
// あると、環境変数を読んで作業ツリーや報告ファイルに書き、それが draft PR として
// PUBLIC リポジトリに出る経路が成立する（CNP で外向き通信を塞いでも、PR は正規の経路）。
//
// このプロセスは別コンテナ（別 uid、エージェントから読めない環境）で動き、
// キーはここにしか無い。エージェントが渡してくる Authorization / x-api-key は捨てる。
// 難読化しようが分割しようが、エージェントの側に元の値が存在しない。
'use strict'
const http = require('node:http')
const https = require('node:https')

const TOKEN = process.env.OPENROUTER_TOKEN
const PORT = Number(process.env.BROKER_PORT || 8787)
const UPSTREAM = process.env.BROKER_UPSTREAM || 'openrouter.ai'

if (!TOKEN) {
  console.error('openrouter-broker: OPENROUTER_TOKEN is not set')
  process.exit(1)
}

// クライアントが名乗る資格情報は一切信用せず捨てる。hop-by-hop も落とす。
const DROP = new Set([
  'authorization',
  'x-api-key',
  'proxy-authorization',
  'host',
  'connection',
  'keep-alive',
  'transfer-encoding',
  'upgrade',
])

const agent = new https.Agent({ keepAlive: true })

const server = http.createServer((req, res) => {
  const headers = {}
  for (const [key, value] of Object.entries(req.headers)) {
    if (!DROP.has(key.toLowerCase())) headers[key] = value
  }
  headers.authorization = `Bearer ${TOKEN}`
  headers.host = UPSTREAM

  const upstream = https.request(
    { host: UPSTREAM, port: 443, path: req.url, method: req.method, headers, agent },
    (upstreamRes) => {
      res.writeHead(upstreamRes.statusCode || 502, upstreamRes.headers)
      upstreamRes.pipe(res)
    },
  )

  // 本文は決してログに出さない（プロンプトも応答も通る）。出すのは状態だけ。
  upstream.on('error', (err) => {
    console.error(`openrouter-broker: upstream error: ${err.message}`)
    if (!res.headersSent) res.writeHead(502, { 'content-type': 'text/plain' })
    res.end('openrouter-broker: upstream error\n')
  })
  req.on('error', () => upstream.destroy())
  res.on('close', () => upstream.destroy())

  req.pipe(upstream)
})

// 127.0.0.1 のみ。Pod 内のネットワーク名前空間は共有されるので、同じ Pod の
// コンテナからは届き、外からは届かない。
server.listen(PORT, '127.0.0.1', () => {
  console.error(`openrouter-broker: listening on 127.0.0.1:${PORT} -> ${UPSTREAM}`)
})

for (const signal of ['SIGTERM', 'SIGINT']) {
  process.on(signal, () => server.close(() => process.exit(0)))
}
