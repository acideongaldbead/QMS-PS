/**
 * ledger.mjs
 *
 * Drives the complaint ledger in a real browser: the two tabs, the simple and
 * advanced filters, sorting, paging controls, column settings, row selection,
 * the Excel export and the jump into a complaint. The API half of task 2.9 is
 * scripts/verify-ledger.ps1.
 *
 * The rows the script asserts on are found by a keyword the PowerShell wrapper
 * puts on the complaints it creates, so the demo data in the database does not
 * make the run flaky.
 *
 * Usage:
 *   node ledger.mjs --marker=UILEDGER --out=<dir> --edge=<path>
 *                   [--base=http://localhost:8080] [--user=siyuan.li]
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
const marker = argv.marker ?? 'UILEDGER'
const user = argv.user ?? 'siyuan.li'
const password = argv.password ?? 'Qms@2026'

if (!edge) {
  console.error('need --edge=<path>')
  process.exit(2)
}
fs.mkdirSync(outDir, { recursive: true })

const steps = []
function note(name, ok, detail = '') {
  steps.push({ name, ok, detail })
  console.log(`  ${ok ? 'PASS' : 'FAIL'}  ${name}${!ok && detail ? '  -> ' + detail : ''}`)
}

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

/** Remembers the export response: the workbook is a download, not a rendered page. */
let exportStatus = 0
let exportType = ''
page.on('response', (res) => {
  if (res.url().includes('/api/complaints/export')) {
    exportStatus = res.status()
    exportType = res.headers()['content-type'] ?? ''
  }
})

async function clickText(text, scope = 'body') {
  const ok = await page.evaluate(
    (t, s) => {
      const root = document.querySelector(s) || document.body
      const els = Array.from(root.querySelectorAll('button, .el-tabs__item, .el-radio-button, .el-button'))
      // offsetParent filters out the hidden duplicate Element renders for a table's
      // fixed columns; clicking that clone does nothing.
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
  await wait(600)
  return ok
}

/** Element renders a checkbox as a label, so clickText's button scan misses it. */
async function clickCheckbox(label, scope = 'body') {
  const ok = await page.evaluate(
    (t, s) => {
      const root = document.querySelector(s) || document.body
      const boxes = Array.from(root.querySelectorAll('.el-checkbox'))
      const target = boxes.find((b) => b.textContent.includes(t) && b.offsetParent !== null)
      if (!target) return false
      target.click()
      return true
    },
    label,
    scope
  )
  await wait(500)
  return ok
}

async function clickColumnHeader(label) {
  const ok = await page.evaluate((t) => {
    const headers = Array.from(document.querySelectorAll('.el-table__header-wrapper th'))
    const target = headers.find((th) => th.textContent.includes(t))
    if (!target) return false
    target.click()
    return true
  }, label)
  await wait(1200)
  return ok
}

async function typeByPlaceholder(placeholder, value) {
  const input = await page.$(`input[placeholder="${placeholder}"], textarea[placeholder="${placeholder}"]`)
  if (!input) throw new Error(`no field with placeholder "${placeholder}"`)
  await input.click({ clickCount: 3 })
  await input.type(String(value))
}

async function shot(name) {
  const file = path.join(outDir, `ledger-${name}.png`)
  await page.screenshot({ path: file })
  return file
}

/** The toolbar's own count, which is server-driven and immune to fixed-column clones. */
async function totalCount() {
  return page.evaluate(() => {
    const m = document.body.innerText.match(/共\s*(\d+)\s*条记录/)
    return m ? Number(m[1]) : -1
  })
}

async function selectedCount() {
  return page.evaluate(() => {
    const m = document.body.innerText.match(/已选\s*(\d+)\s*条/)
    return m ? Number(m[1]) : -1
  })
}

/** The complaint ids in the order they are rendered. */
async function rowIds() {
  return page.evaluate(() => {
    const body = document.querySelector('.el-table__body-wrapper')
    if (!body) return []
    return body.innerText.match(/C\d{9}/g) ?? []
  })
}

async function headerLabels() {
  return page.evaluate(() =>
    Array.from(document.querySelectorAll('.el-table__header-wrapper th')).map((th) =>
      th.innerText.trim()
    )
  )
}

try {
  // --- sign in as the quality engineer -------------------------------------
  await page.goto(`${base}/#/login`, { waitUntil: 'networkidle2', timeout: 40000 })
  await page.evaluate(() => localStorage.clear())
  await page.reload({ waitUntil: 'networkidle2' })
  await page.waitForSelector('input[type="text"]', { timeout: 20000 })
  await page.type('input[type="text"]', user)
  await page.type('input[type="password"]', password)
  await page.click('button[type="submit"]')
  await page.waitForFunction(() => !!document.querySelector('.app-sidebar .nav-item'), { timeout: 25000 })

  await page.goto(`${base}/#/complaints`, { waitUntil: 'networkidle2', timeout: 40000 })
  await page.waitForSelector('.el-table__row', { timeout: 25000 })
  await wait(1200)
  await shot('1-loaded')

  const loaded = await totalCount()
  note('the ledger opens with rows', loaded > 0, `count=${loaded}`)

  const tabs = await page.evaluate(() => {
    const t = Array.from(document.querySelectorAll('.pill-tab')).map((el) => el.innerText.trim())
    return t.join(' | ')
  })
  note('both tabs are present with their counters', tabs.includes('与我相关') && tabs.includes('全部数据'), tabs)

  const hint = await page.evaluate(() => document.body.innerText)
  note('the tab explains what it filters', hint.includes('仅显示我承担负责人'))

  const defaultTabOn = await page.evaluate(() => {
    const on = document.querySelector('.pill-tab.is-on')
    return on ? on.innerText.trim() : ''
  })
  note('the ledger opens on the "related to me" tab', defaultTabOn.includes('与我相关'), defaultTabOn)

  // --- keyword search, still on the default tab ----------------------------
  await typeByPlaceholder('模糊查询：流程ID / 客户参考ID / 客户名称 / 产品编码', marker)
  if (!(await clickText('查询'))) throw new Error('no search button')
  await wait(1400)
  await shot('2-searched')

  // Two rows carry the marker, but only one of them is the engineer's.
  const mineScoped = await totalCount()
  const mineText = await page.evaluate(() => document.body.innerText)
  note('the keyword narrows the result to my seeded row', mineScoped === 1, `count=${mineScoped}`)
  note(
    'the other owner\'s complaint is filtered out by the mine tab',
    mineText.includes(`${marker}-A`) && !mineText.includes(`${marker}-B`)
  )

  // --- the "all" tab --------------------------------------------------------
  if (!(await clickText('全部数据'))) throw new Error('no "all" tab')
  await wait(1400)
  await shot('3-all')
  const allScope = await totalCount()
  const allText = await page.evaluate(() => document.body.innerText)
  note('the all tab keeps the keyword filter and shows both', allScope === 2, `count=${allScope}`)
  note(
    'both seeded complaints are listed on the all tab',
    allText.includes(`${marker}-A`) && allText.includes(`${marker}-B`),
    'the reference ids are not both on screen'
  )

  if (!(await clickText('与我相关'))) throw new Error('no "mine" tab')
  await wait(1400)
  await shot('4-mine')
  const mineScopeBack = await totalCount()
  note('switching back to the mine tab drops the other row', mineScopeBack === 1, `count=${mineScopeBack}`)

  // --- advanced search + overdue checkbox ----------------------------------
  if (!(await clickText('高级搜索'))) throw new Error('no advanced search toggle')
  await wait(700)
  await shot('5-advanced')
  const advancedText = await page.evaluate(() => document.body.innerText)
  note('the advanced panel exposes the date and owner filters', advancedText.includes('投诉负责人'))

  // Widen back to all data so the overdue filter is the only thing narrowing.
  if (!(await clickText('全部数据'))) throw new Error('no "all" tab before the overdue filter')
  await wait(1200)
  if (!(await clickCheckbox('仅看已超期单据'))) throw new Error('no overdue checkbox')
  if (!(await clickText('查询'))) throw new Error('no search button after the overdue tick')
  await wait(1400)
  await shot('6-overdue')
  const overdueOnly = await totalCount()
  note('the overdue filter leaves only the overdue complaint', overdueOnly === 1, `count=${overdueOnly}`)

  // back to the unfiltered-by-overdue view, still scoped by the keyword
  if (!(await clickText('重置'))) throw new Error('no reset button')
  await wait(1200)
  await typeByPlaceholder('模糊查询：流程ID / 客户参考ID / 客户名称 / 产品编码', marker)
  if (!(await clickText('查询'))) throw new Error('no search button after reset')
  await wait(1400)

  // --- sorting (needs more than one row on screen) --------------------------
  // Sorted on the priority rather than the id: the default order already puts the
  // overdue complaint first, which is the same order ascending ids would give.
  const beforeSort = await rowIds()
  if (!(await clickColumnHeader('优先级'))) throw new Error('no 优先级 header to sort by')
  await wait(1400)
  await shot('7-sorted')
  const afterSort = await rowIds()
  note(
    'clicking a column header reorders the list',
    beforeSort.length >= 2 && beforeSort.join(',') !== afterSort.join(','),
    `${beforeSort.join(',')} -> ${afterSort.join(',')}`
  )

  // --- column settings ------------------------------------------------------
  if (!(await clickText('列设置'))) throw new Error('no column settings trigger')
  await wait(700)
  if (!(await clickCheckbox('状态', '.el-popover'))) throw new Error('no 状态 toggle in the column menu')
  await wait(700)
  await shot('8-columns')
  const headers = await headerLabels()
  note('hiding a column removes its header', !headers.includes('状态'), headers.join(','))

  // --- selection + export ---------------------------------------------------
  await page.click('.el-table__header-wrapper .el-checkbox')
  await wait(900)
  await shot('9-selected')
  const chosen = await selectedCount()
  note('ticking the header selects the page', chosen > 0, `selected=${chosen}`)

  if (!(await clickText('导出'))) throw new Error('no export button')
  await wait(3500)
  await shot('10-exported')
  note('the export responds 200', exportStatus === 200, `status=${exportStatus}`)
  note(
    'the export is an xlsx workbook',
    exportType.includes('spreadsheetml.sheet'),
    `content-type=${exportType}`
  )

  // --- copy a complaint -----------------------------------------------------
  if (!(await clickText('复制'))) throw new Error('no copy action on the row')
  await page.waitForFunction(() => /#\/complaints\/new/.test(window.location.hash), { timeout: 20000 })
  await wait(1800)
  await shot('11-copy')
  const copyHash = await page.evaluate(() => window.location.hash)
  const copyText = await page.evaluate(() => document.body.innerText)
  note('the copy action opens the registration wizard', /#\/complaints\/new/.test(copyHash), copyHash)
  note(
    'the wizard says it was prefilled from a history complaint',
    copyText.includes('已按历史投诉预填')
  )
  const sourceId = (/copyFrom=(C\d{9})/.exec(copyHash) ?? [])[1]
  note(
    'the wizard names the source complaint it copied',
    !!sourceId && copyText.includes(sourceId),
    `source=${sourceId}`
  )

  // --- jump into the complaint ---------------------------------------------
  await page.goto(`${base}/#/complaints`, { waitUntil: 'networkidle2', timeout: 40000 })
  await page.waitForSelector('.el-table__row', { timeout: 25000 })
  await wait(1200)
  if (!(await clickText('查看'))) throw new Error('no view action on the row')
  await page.waitForFunction(() => /#\/complaints\/C\d+/.test(window.location.hash), { timeout: 20000 })
  await wait(1500)
  await shot('12-detail')
  const hash = await page.evaluate(() => window.location.hash)
  note('the row action opens the complaint detail', /#\/complaints\/C\d{9}/.test(hash), hash)
} catch (err) {
  note('ledger page run', false, err.message)
  try {
    await shot('error')
  } catch {
    /* ignore */
  }
} finally {
  await context.close().catch(() => {})
  await browser.close()
}

fs.writeFileSync(path.join(outDir, 'ledger_report.json'), JSON.stringify({ marker, steps }, null, 2))
const failed = steps.filter((s) => !s.ok).length
console.log('')
console.log(`  RESULT : ${failed === 0 ? 'PASS' : 'FAIL (' + failed + ')'}   marker=${marker}`)
if (failed !== 0) process.exit(1)
