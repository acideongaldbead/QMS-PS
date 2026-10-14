/**
 * d4.mjs
 *
 * Drives the D4 tab in a real browser: create the root cause through the UI,
 * open the 3x5Why mind map and add a level, save a version, then open the
 * fishbone editor, enter a cause and check the diagram renders.
 *
 * Usage:
 *   node d4.mjs --complaint=C202600001 --out=<dir> --edge=<path>
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

const steps = []
function note(name, ok, detail = '') {
  steps.push({ name, ok, detail })
  console.log(`  ${ok ? 'PASS' : 'FAIL'}  ${name}${!ok && detail ? '  -> ' + detail : ''}`)
}

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

async function typeByPlaceholder(placeholder, value, scope = 'body') {
  const input = await page.$(`${scope} input[placeholder="${placeholder}"], ${scope} textarea[placeholder="${placeholder}"]`)
  if (!input) throw new Error(`no field with placeholder "${placeholder}" in ${scope}`)
  await input.click({ clickCount: 3 })
  await input.type(String(value))
}

async function shot(name) {
  const file = path.join(outDir, `d4-${name}.png`)
  await page.screenshot({ path: file })
  return file
}

try {
  // --- sign in and open the detail page ------------------------------------
  await page.goto(`${base}/#/login`, { waitUntil: 'networkidle2', timeout: 40000 })
  await page.evaluate(() => localStorage.clear())
  await page.reload({ waitUntil: 'networkidle2' })
  await page.waitForSelector('input[type="text"]', { timeout: 20000 })
  await page.type('input[type="text"]', user)
  await page.type('input[type="password"]', password)
  await page.click('button[type="submit"]')
  await page.waitForFunction(() => !!document.querySelector('.app-sidebar .nav-item'), { timeout: 25000 })

  await page.goto(`${base}/#/complaints/${complaint}`, { waitUntil: 'networkidle2', timeout: 40000 })
  await page.waitForSelector('.stage-bar', { timeout: 25000 })
  await wait(1200)

  if (!(await clickText('D4 根因分析'))) throw new Error('could not open the D4 tab')
  await wait(1500)
  await shot('1-tab')

  // --- create a root cause through the UI ----------------------------------
  if (!(await clickText('新增根因'))) throw new Error('could not open the root-cause dialog')
  await wait(900)
  await typeByPlaceholder('完整描述根因，可在附件中心挂分析图片', 'Mold temperature drifted after the tool change.', '.el-dialog')
  await typeByPlaceholder('用于报表与知识检索的短描述', 'Mold temperature drift', '.el-dialog')
  await shot('2-dialog')
  if (!(await clickText('保存', '.el-dialog'))) throw new Error('no save button in the root-cause dialog')
  await wait(2500)
  await shot('3-created')

  const afterCreate = await page.evaluate(() => document.body.innerText)
  note('the root cause is listed', /RC\d{9}/.test(afterCreate), 'no root-cause id on the page')
  note('the ownership tag is shown', afterCreate.includes('内部'), 'ownership tag missing')

  // --- the 3x5Why mind map -------------------------------------------------
  if (!(await clickText('3x5Why'))) throw new Error('could not open the 3x5Why editor')
  await wait(3500)
  await shot('4-mindmap')

  const mindRendered = await page.evaluate(() => {
    const host = document.querySelector('.mind-host')
    return !!host && (host.querySelector('.map-container') !== null || host.querySelector('svg') !== null)
  })
  note('the mind map renders', mindRendered, 'no map container inside .mind-host')

  const topicCount = await page.evaluate(() => document.querySelectorAll('.mind-host me-tpc, .mind-host [data-nodeid]').length)
  note('the mind map has a root and a first reason', topicCount >= 2, `nodes=${topicCount}`)

  // Adding a level is the interaction the business described: select the reason,
  // then press the "+ next level" button.
  //
  // A real mouse click, not a synthetic click(): the library starts selection on
  // mousedown (it also supports dragging), so a bare click event selects nothing
  // and the add would be refused with "please select a node first".
  const topicHandles = await page.$$('.mind-host me-tpc')
  if (topicHandles.length < 2) throw new Error(`expected at least 2 topics, found ${topicHandles.length}`)
  await topicHandles[1].click()
  await wait(700)

  const selected = await page.evaluate(
    () => document.querySelectorAll('.mind-host .selected, .mind-host me-tpc.selected').length
  )
  note('clicking a node selects it', selected > 0, 'nothing became selected')

  if (!(await clickText('+ 下一层（子节点）'))) throw new Error('no add-child button')
  await wait(1200)
  const afterAdd = await page.evaluate(() => document.querySelectorAll('.mind-host me-tpc, .mind-host [data-nodeid]').length)
  note('a deeper level can be added', afterAdd > topicCount, `nodes ${topicCount} -> ${afterAdd}`)
  await shot('5-mindmap-added')

  if (!(await clickText('保存为新版本'))) throw new Error('no save button for the analysis')
  await wait(2500)
  await shot('6-mindmap-saved')

  const afterSave = await page.evaluate(() => document.body.innerText)
  note('the analysis is saved as a version', afterSave.includes('版本历史'), 'no version history shown')

  // --- the fishbone editor -------------------------------------------------
  await page.keyboard.press('Escape')
  await wait(1000)
  if (!(await clickText('鱼骨图'))) throw new Error('could not open the fishbone editor')
  await wait(5000)
  await shot('7-fishbone')

  const fishRendered = await page.evaluate(() => {
    const svg = document.querySelector('.fb-svg svg')
    return !!svg && svg.innerHTML.length > 0
  })
  note('the fishbone diagram renders', fishRendered, 'no svg inside .fb-svg')

  const hasSixM = await page.evaluate(() => document.body.innerText)
  note('the six categories are offered', ['人', '机', '料', '法', '环', '测'].every((m) => hasSixM.includes(m)), 'a category is missing')

  // Enter a cause and check the diagram picks it up.
  if (!(await clickText('+ 添加原因'))) throw new Error('no add-cause button')
  await wait(500)
  await typeByPlaceholder('原因', 'Mold temperature drift')
  await wait(1500)
  await shot('8-fishbone-filled')

  // Read the whole preview container: Mermaid leaves a hidden measuring SVG
  // behind, and it may place labels as HTML alongside the diagram, so reading one
  // SVG would miss the text.
  const diagramText = await page.evaluate(() => {
    const host = document.querySelector('.fb-svg')
    return host ? host.textContent.replace(/\s+/g, ' ') : ''
  })
  // Mermaid lays a multi-word label out as several tspans, so textContent joins
  // the words without spaces ("Moldtemperaturedrift"). Compare with whitespace
  // removed on both sides.
  const squeeze = (s) => s.replace(/\s+/g, '')
  note(
    'the typed cause appears in the diagram',
    squeeze(diagramText).includes(squeeze('Mold temperature drift')),
    squeeze(diagramText).slice(-160)
  )

  if (!(await clickText('保存为新版本'))) throw new Error('no save button for the fishbone')
  await wait(2500)
  await shot('9-fishbone-saved')

  const afterFishSave = await page.evaluate(() => document.body.innerText)
  note('the fishbone is saved', afterFishSave.includes('已保存为'), 'no save confirmation')
} catch (err) {
  note('D4 page run', false, err.message)
  try {
    await shot('error')
  } catch {
    /* ignore */
  }
} finally {
  await context.close().catch(() => {})
  await browser.close()
}

fs.writeFileSync(path.join(outDir, 'd4_report.json'), JSON.stringify({ complaint, steps }, null, 2))
const failed = steps.filter((s) => !s.ok).length
console.log('')
console.log(`  RESULT : ${failed === 0 ? 'PASS' : 'FAIL (' + failed + ')'}   complaint=${complaint}`)
if (failed !== 0) process.exit(1)
