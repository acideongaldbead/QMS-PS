/**
 * lazy-load.mjs
 *
 * Proves the heavy editors load on demand by recording what the browser actually
 * requests, stage by stage. Build output alone cannot show this: a chunk can be
 * emitted and still be fetched eagerly, and a manualChunks rule can merge many
 * lazy chunks into one that downloads in full.
 *
 * Stages: login -> complaint detail -> D4 tab -> 3x5Why editor -> fishbone editor.
 *
 * Usage:
 *   node lazy-load.mjs --complaint=C202600001 --out=<dir> --edge=<path>
 */
import fs from 'node:fs'
import path from 'node:path'
import puppeteer from 'puppeteer-core'

const argv = Object.fromEntries(
  process.argv.slice(2).map((arg) => {
    const [key, ...rest] = arg.replace(/^--/, '').split('=')
    return [key, rest.join('=')]
  })
)

const base = argv.base ?? 'http://localhost:8080'
const outDir = argv.out ?? '.'
const edge = argv.edge
const complaint = argv.complaint
const user = argv.user ?? 'siyuan.li'
const password = argv.password ?? 'Qms@2026'

if (!edge || !complaint) {
  console.error('need --edge=<path> and --complaint=<id>')
  process.exit(2)
}
fs.mkdirSync(outDir, { recursive: true })

const browser = await puppeteer.launch({
  executablePath: edge,
  headless: true,
  args: ['--no-first-run', '--no-default-browser-check', '--disable-gpu', '--hide-scrollbars']
})
const context = browser.createBrowserContext
  ? await browser.createBrowserContext()
  : await browser.createIncognitoBrowserContext()
const page = await context.newPage()
await page.setViewport({ width: 1680, height: 1080 })
const wait = (ms) => new Promise((r) => setTimeout(r, ms))

/** Every asset the page has pulled, with its size where the server reported one. */
const assets = []
page.on('response', async (res) => {
  const m = res.url().match(/\/assets\/([^/?#]+)$/)
  if (!m) return
  let bytes = 0
  try {
    const len = res.headers()['content-length']
    bytes = len ? Number(len) : (await res.buffer().catch(() => Buffer.alloc(0))).length
  } catch {
    bytes = 0
  }
  assets.push({ name: m[1], bytes })
})

/** Names pulled so far, since a stage boundary. */
const since = (index) => assets.slice(index).map((a) => a.name)
const bytesSince = (index) => assets.slice(index).reduce((sum, a) => sum + a.bytes, 0)
const kb = (n) => Math.round(n / 1024) + ' KB'

const steps = []
function note(name, ok, detail = '') {
  steps.push({ name, ok, detail })
  console.log(`  ${ok ? 'PASS' : 'FAIL'}  ${name}${!ok && detail ? '  -> ' + detail : ''}`)
}

const matchesAny = (names, re) => names.some((n) => re.test(n))

async function clickText(text, scope = 'body') {
  const ok = await page.evaluate(
    (t, s) => {
      const root = document.querySelector(s) || document.body
      const els = Array.from(root.querySelectorAll('button, .el-tabs__item, .el-button'))
      const target = els.find(
        (el) => (el.textContent.trim() === t || el.textContent.includes(t)) && el.offsetParent !== null
      )
      if (!target) return false
      target.click()
      return true
    },
    text,
    scope
  )
  await wait(700)
  return ok
}

try {
  // --- stage 1: login -------------------------------------------------------
  let mark = assets.length
  await page.goto(`${base}/#/login`, { waitUntil: 'networkidle2', timeout: 40000 })
  await page.evaluate(() => localStorage.clear())
  await page.reload({ waitUntil: 'networkidle2' })
  await page.waitForSelector('input[type="text"]', { timeout: 20000 })
  await page.type('input[type="text"]', user)
  await page.type('input[type="password"]', password)
  await page.click('button[type="submit"]')
  await page.waitForFunction(() => !!document.querySelector('.app-sidebar .nav-item'), { timeout: 25000 })
  await wait(1200)

  const loginAssets = since(mark)
  note(
    'the login page pulls no editor code',
    !matchesAny(loginAssets, /mermaid|MindElixir|vendor-mermaid/i),
    loginAssets.filter((n) => /mermaid|MindElixir/i.test(n)).join(', ')
  )
  console.log(`         login fetched ${loginAssets.length} assets, ${kb(bytesSince(mark))}`)

  // --- stage 2: the complaint detail page ----------------------------------
  mark = assets.length
  await page.goto(`${base}/#/complaints/${complaint}`, { waitUntil: 'networkidle2', timeout: 40000 })
  await page.waitForSelector('.stage-bar', { timeout: 25000 })
  await wait(1500)

  const detailAssets = since(mark)
  note(
    'opening the complaint pulls no editor code',
    !matchesAny(detailAssets, /mermaid|MindElixir|vendor-mermaid/i),
    detailAssets.filter((n) => /mermaid|MindElixir/i.test(n)).join(', ')
  )
  console.log(`         detail page fetched ${detailAssets.length} assets, ${kb(bytesSince(mark))}`)

  // --- stage 3: the D4 tab (neither editor is mounted yet) -----------------
  mark = assets.length
  if (!(await clickText('D4 根因分析'))) throw new Error('could not open the D4 tab')
  await wait(1500)

  const d4Assets = since(mark)
  note(
    'the D4 tab alone still pulls no editor code',
    !matchesAny(d4Assets, /mermaid|MindElixir|vendor-mermaid/i),
    d4Assets.filter((n) => /mermaid|MindElixir/i.test(n)).join(', ')
  )
  console.log(`         D4 tab fetched ${d4Assets.length} assets, ${kb(bytesSince(mark))}`)

  // --- stage 4: the 3x5Why mind map ---------------------------------------
  mark = assets.length
  if (!(await clickText('3x5Why'))) throw new Error('could not open the 3x5Why editor')
  await wait(3500)

  const whyAssets = since(mark)
  note(
    'the 3x5Why editor loads mind-elixir on demand',
    matchesAny(whyAssets, /MindElixir/i),
    'mind-elixir was never fetched'
  )
  note(
    'the 3x5Why editor does not drag in mermaid',
    !matchesAny(whyAssets, /mermaid\.core|mermaid\.esm/i),
    whyAssets.filter((n) => /mermaid/i.test(n)).join(', ')
  )
  console.log(`         3x5Why fetched ${whyAssets.length} assets, ${kb(bytesSince(mark))}`)

  // --- stage 5: the fishbone editor ---------------------------------------
  await page.keyboard.press('Escape')
  await wait(800)
  mark = assets.length
  if (!(await clickText('鱼骨图'))) throw new Error('could not open the fishbone editor')
  await wait(5000)

  const fishAssets = since(mark)
  note(
    'the fishbone editor loads mermaid on demand',
    matchesAny(fishAssets, /mermaid\.core|mermaid\.esm/i),
    'mermaid was never fetched'
  )
  note(
    'the ishikawa diagram chunk is fetched',
    matchesAny(fishAssets, /ishikawaDiagram/i),
    fishAssets.join(', ')
  )
  note(
    'no other diagram engine is downloaded',
    !matchesAny(fishAssets, /^(elk|cynefin|cytoscape|katex)/i),
    fishAssets.filter((n) => /^(elk|cynefin|cytoscape|katex)/i.test(n)).join(', ')
  )
  console.log(`         fishbone fetched ${fishAssets.length} assets, ${kb(bytesSince(mark))}`)

  const totalBytes = assets.reduce((s, a) => s + a.bytes, 0)
  console.log('')
  console.log(`         whole session: ${assets.length} assets, ${kb(totalBytes)}`)
} catch (err) {
  note('lazy-load run', false, err.message)
} finally {
  await context.close().catch(() => {})
  await browser.close()
}

fs.writeFileSync(
  path.join(outDir, 'lazy_load_report.json'),
  JSON.stringify({ complaint, assets, steps }, null, 2)
)
const failed = steps.filter((s) => !s.ok).length
console.log('')
console.log(`  RESULT : ${failed === 0 ? 'PASS' : 'FAIL (' + failed + ')'}`)
if (failed !== 0) process.exit(1)
