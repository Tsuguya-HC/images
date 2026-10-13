// openrouter-broker の振る舞いテスト。claude-code イメージの中で非 root（65532）として
//
//   docker run --rm -u 65532:65532 -v .../openrouter-broker.test.js:/tmp/t.js:ro <image> node /tmp/t.js
//
// のように呼ぶ想定（BROKER_JS で対象を差し替えられる）。ネットワークには出ない:
// 上流は 127.0.0.1:443 に立てた偽の HTTPS サーバーで、ブローカーには
// BROKER_UPSTREAM=localhost と、その自己署名証明書を NODE_EXTRA_CA_CERTS で渡す。
// 443 を非 root で listen できるのは、Docker がコンテナに
// net.ipv4.ip_unprivileged_port_start=0 を入れているから。
//
// 見ているのはブローカーが約束していること:
//   - 上流に届く Authorization は実キーだけで、エージェントが名乗る資格情報は落ちる
//   - 許可するのは POST /api/v1/messages（と下位パス）だけで、それ以外は上流に届かない
//   - OPENROUTER_TOKEN が無ければ起動しない
//   - SIGTERM で応答待ちの接続が残っていても期限内に降りる
// 1 項目でも落ちたら非ゼロで終わる。
'use strict'
const { spawn, execFileSync } = require('node:child_process')
const fs = require('node:fs')
const http = require('node:http')
const https = require('node:https')
const os = require('node:os')
const path = require('node:path')

const BROKER = process.env.BROKER_JS || '/usr/local/bin/openrouter-broker.js'
const TOKEN = 'sk-broker-test-real-key'
const PORT = 18787

let failed = 0
function check(desc, ok, detail) {
  if (ok) {
    console.log(`ok: ${desc}`)
  } else {
    console.error(`FAIL: ${desc}${detail ? ` (${detail})` : ''}`)
    failed = 1
  }
}

const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'broker-test-'))
const key = path.join(dir, 'key.pem')
const cert = path.join(dir, 'cert.pem')
execFileSync('openssl', [
  'req', '-x509', '-newkey', 'rsa:2048', '-nodes', '-days', '1',
  '-keyout', key, '-out', cert, '-subj', '/CN=localhost', '-addext', 'subjectAltName=DNS:localhost',
], { stdio: 'ignore' })

// 上流に届いたリクエストを全部残す。
const seen = []
let hung = 0
// /hang で終わるパスには応答しない（停止時に応答待ちの接続を残すため）。
const upstream = https.createServer({ key: fs.readFileSync(key), cert: fs.readFileSync(cert) }, (req, res) => {
  if (req.url.endsWith('/hang')) {
    hung += 1
    req.resume()
    return
  }
  const chunks = []
  req.on('data', (c) => chunks.push(c))
  req.on('end', () => {
    seen.push({ method: req.method, url: req.url, headers: req.headers, body: Buffer.concat(chunks).toString() })
    res.writeHead(200, { 'content-type': 'application/json' })
    res.end('{"upstream":true}')
  })
})

function startBroker(env) {
  return spawn(process.execPath, [BROKER], {
    env: { PATH: process.env.PATH, BROKER_UPSTREAM: 'localhost', BROKER_PORT: String(PORT), NODE_EXTRA_CA_CERTS: cert, ...env },
    stdio: ['ignore', 'ignore', 'pipe'],
  })
}

function waitListening(child) {
  return new Promise((resolve, reject) => {
    let err = ''
    const timer = setTimeout(() => reject(new Error(`broker did not start: ${err}`)), 5000)
    child.stderr.on('data', (d) => {
      err += d
      if (err.includes('listening on')) {
        clearTimeout(timer)
        resolve()
      }
    })
    child.on('exit', (code) => {
      clearTimeout(timer)
      reject(new Error(`broker exited ${code}: ${err}`))
    })
  })
}

function waitExit(child, ms) {
  return new Promise((resolve) => {
    if (child.exitCode !== null) return resolve(child.exitCode)
    const timer = setTimeout(() => resolve('timeout'), ms)
    child.on('exit', (code) => {
      clearTimeout(timer)
      resolve(code)
    })
  })
}

function send(method, reqPath, { headers = {}, body = '', agent = false } = {}) {
  return new Promise((resolve, reject) => {
    const req = http.request({ host: '127.0.0.1', port: PORT, method, path: reqPath, headers, agent }, (res) => {
      const chunks = []
      res.on('data', (c) => chunks.push(c))
      res.on('end', () => resolve({ status: res.statusCode, body: Buffer.concat(chunks).toString() }))
    })
    req.on('error', reject)
    req.end(body)
  })
}

async function main() {
  // OPENROUTER_TOKEN が無いときは起動しない。
  const noToken = startBroker({})
  let noTokenErr = ''
  noToken.stderr.on('data', (d) => { noTokenErr += d })
  const noTokenCode = await waitExit(noToken, 5000)
  check('broker refuses to start without OPENROUTER_TOKEN', noTokenCode === 1 && noTokenErr.includes('OPENROUTER_TOKEN is not set'),
    `exit ${noTokenCode}: ${noTokenErr.trim()}`)

  await new Promise((resolve) => upstream.listen(443, '127.0.0.1', resolve))
  const broker = startBroker({ OPENROUTER_TOKEN: TOKEN })
  await waitListening(broker)

  // 許可した経路: 実キーに付け替えて上流へ。
  seen.length = 0
  const ok = await send('POST', '/api/v1/messages', {
    headers: { authorization: 'Bearer agent-made-up', 'x-api-key': 'agent-made-up', 'proxy-authorization': 'Basic eA==', 'content-type': 'application/json' },
    body: '{"model":"m"}',
  })
  const got = seen[0]
  check('POST /api/v1/messages is forwarded', ok.status === 200 && seen.length === 1 && got.url === '/api/v1/messages',
    `status ${ok.status}, upstream saw ${JSON.stringify(seen.map((s) => s.url))}`)
  check('upstream gets the real key, not the agent\'s', got && got.headers.authorization === `Bearer ${TOKEN}`,
    got && `authorization: ${got.headers.authorization}`)
  check('x-api-key and proxy-authorization from the agent are dropped',
    got && !('x-api-key' in got.headers) && !('proxy-authorization' in got.headers),
    got && JSON.stringify(got.headers))
  check('Host is rewritten to the upstream', got && got.headers.host === 'localhost', got && `host: ${got.headers.host}`)
  check('request body is passed through', got && got.body === '{"model":"m"}', got && `body: ${got.body}`)

  seen.length = 0
  const sub = await send('POST', '/api/v1/messages/count_tokens', { body: '{}' })
  check('POST under /api/v1/messages/ is forwarded', sub.status === 200 && seen.length === 1 && seen[0].url === '/api/v1/messages/count_tokens',
    `status ${sub.status}, upstream saw ${JSON.stringify(seen.map((s) => s.url))}`)

  // 拒否する経路: 403 を返し、上流には一切届かない。
  for (const [method, reqPath] of [
    ['GET', '/api/v1/messages'],
    ['POST', '/api/v1/keys'],
    ['POST', '/api/v1/auth/key'],
    ['DELETE', '/api/v1/messages'],
  ]) {
    seen.length = 0
    const r = await send(method, reqPath, { body: method === 'GET' ? '' : '{}' })
    check(`${method} ${reqPath} is rejected without reaching upstream`, r.status === 403 && seen.length === 0,
      `status ${r.status}, upstream saw ${JSON.stringify(seen.map((s) => `${s.method} ${s.url}`))}`)
  }

  // 応答待ちの接続を開いたまま SIGTERM。server.close() は idle な接続しか畳まないので、
  // closeAllConnections が無いと callback が返らず、期限（既定 3 秒）まで待たされる。
  const hanging = http.request({ host: '127.0.0.1', port: PORT, method: 'POST', path: '/api/v1/messages/hang', agent: false })
  hanging.on('error', () => {})
  hanging.end('{}')
  // 上流に届いた（= ブローカーが応答待ちになった）のを待ってから止める。
  for (let i = 0; i < 100 && hung === 0; i++) await new Promise((resolve) => setTimeout(resolve, 50))
  check('a request is in flight before SIGTERM', hung === 1, `hung ${hung}`)
  const t0 = Date.now()
  broker.kill('SIGTERM')
  const code = await waitExit(broker, 5000)
  const elapsed = Date.now() - t0
  check('SIGTERM exits 0 well before the shutdown deadline with a request in flight', code === 0 && elapsed < 2000,
    `exit ${code} after ${elapsed} ms`)
  hanging.destroy()
  upstream.closeAllConnections()

  upstream.close()
  fs.rmSync(dir, { recursive: true, force: true })
  process.exit(failed)
}

main().catch((err) => {
  console.error(`FAIL: ${err.stack || err}`)
  process.exit(1)
})
