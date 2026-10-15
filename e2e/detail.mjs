/**
 * detail.mjs
 *
 * Drives the complaint detail page in a real browser against a complaint that
 * already exists: checks the stage bar, opens the sample/logistics tab, creates a
 * shipment and moves a sample into it. This is the UI half of task 2.3; the API
 * half is scripts/verify-logistics.ps1.
 *
 * Usage:
 *   node detail.mjs --complaint=C202600001 --out=<dir> --edge=<path> [--base=...]
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
const user = argv.user ?? 'xiaoran.ma'
const password = argv.password ?? 'Qms@2026'

if (!edge || !complaint) {
  console.error('need --edge=<path> and --complaint=<id>')
  process.exit(2)
}
fs.mkdirSync(outDir, { recursive: true })

const steps = []
function note(name, ok, detail = '') {
  steps.push({ name, ok, detail })
  // The detail is a failure explanation; printing it on success reads as a
  // contradiction and has misled a reader before.
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

/** Clicks a row-action icon through its data-act hook. A fixed column renders a
 *  hidden clone of the button, so the first visible one wins. */
async function clickAct(act) {
  const ok = await page.evaluate((a) => {
    const el = Array.from(document.querySelectorAll(`[data-act="${a}"]`)).find(
      (e) => e.offsetParent !== null
    )
    if (!el) return false
    el.click()
    return true
  }, act)
  await wait(700)
  return ok
}

async function clickText(text, scope = 'body') {
  const ok = await page.evaluate(
    (t, s) => {
      const root = document.querySelector(s) || document.body
      const clickable = Array.from(root.querySelectorAll('button, .el-tabs__item, .el-button'))
      // offsetParent filters out the hidden duplicate Element renders for a table's
      // fixed columns; clicking that clone does nothing.
      const target = clickable.find(
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

/** Picks an option in the nth visible select inside a scope, by label text. */
async function pickSelectIn(scope, index, fragment) {
  const selects = await page.$$(`${scope} .el-select`)
  if (index >= selects.length) throw new Error(`select #${index} not in ${scope} (have ${selects.length})`)
  await selects[index].click()
  await wait(400)
  const clicked = await page.evaluate((f) => {
    const panels = Array.from(document.querySelectorAll('.el-select-dropdown')).filter(
      (d) => d.offsetParent !== null
    )
    const options = panels.flatMap((p) => Array.from(p.querySelectorAll('.el-select-dropdown__item')))
    const target = options.find((o) => o.textContent.includes(f))
    if (!target) return false
    target.click()
    return true
  }, fragment)
  await wait(400)
  if (!clicked) throw new Error(`option "${fragment}" not found`)
}

async function typeByPlaceholder(placeholder, value) {
  const input = await page.$(`input[placeholder="${placeholder}"]`)
  if (!input) throw new Error(`no input with placeholder "${placeholder}"`)
  await input.click({ clickCount: 3 })
  await input.type(String(value))
}

async function shot(name) {
  const file = path.join(outDir, `detail-${name}.png`)
  await page.screenshot({ path: file })
  return file
}

try {
  // --- sign in and open the detail page -------------------------------------
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
  await shot('1-overview')

  const heading = await page.$eval('h1', (e) => e.textContent.trim())
  note('the detail page opens on the complaint', heading === complaint, heading)

  const activeStage = await page.$$eval('.stage-item.is-active .code', (els) =>
    els.map((e) => e.textContent.trim())
  )
  note('the stage bar marks D1 as the current stage', activeStage.includes('D1'), activeStage.join(','))

  const tabLabels = await page.$$eval('.el-tabs__item', (els) => els.map((e) => e.textContent.trim()))
  note('the detail page shows the 8D tabs', tabLabels.length >= 10, `tabs=${tabLabels.length}`)

  // --- sample and logistics tab --------------------------------------------
  if (!(await clickText('样品与物流'))) throw new Error('could not open the sample tab')
  await wait(1200)
  await shot('2-samples')

  const sampleRows = await page.$$eval('.el-table__row td:first-child', (els) =>
    els.map((e) => e.textContent.trim())
  )
  note(
    'the sample registered during registration is listed',
    sampleRows.some((t) => /^S\d{9}$/.test(t)),
    sampleRows.slice(0, 3).join(', ')
  )

  // --- create a shipment through the UI ------------------------------------
  if (!(await clickText('新增物流批次'))) throw new Error('could not open the shipment dialog')
  await wait(900)

  await pickSelectIn('.el-dialog', 0, '刘丹茜') // sender
  await pickSelectIn('.el-dialog', 1, '王振宇') // receiver
  await typeByPlaceholder('Carrier Name', 'SF Express')
  await typeByPlaceholder('Carrier Tracking Number', 'SF9876543210')
  await typeByPlaceholder('Shipment ID', 'SF-UI-1')

  // the first el-input-number inside the dialog is the shipped quantity
  const qtyInput = await page.$('.el-dialog .el-input-number input')
  if (qtyInput) {
    await qtyInput.click({ clickCount: 3 })
    await qtyInput.type('7')
  }
  await wait(300)
  await shot('3-shipment-dialog')

  if (!(await clickText('保存', '.el-dialog'))) throw new Error('no save button in the dialog')
  await wait(2200)
  await shot('4-shipment-created')

  const shipmentRows = await page.$$eval('.el-table__row', (rows) =>
    rows.map((r) => r.textContent.trim())
  )
  note(
    'the shipment appears in the batch list',
    shipmentRows.some((t) => t.includes('SF-UI-1')),
    shipmentRows.length + ' rows'
  )

  // --- the action is icon-only, so its name lives in the hover tooltip ------
  const detailBox = await page.evaluate(() => {
    const b = Array.from(document.querySelectorAll('.row-act[data-act="detail"]')).find(
      (e) => e.offsetParent !== null
    )
    if (!b) return null
    const r = b.getBoundingClientRect()
    return { x: r.left + r.width / 2, y: r.top + r.height / 2 }
  })
  if (detailBox) await page.mouse.move(detailBox.x, detailBox.y)
  await wait(900)
  const actionTip = await page.evaluate(() =>
    Array.from(document.querySelectorAll('.el-popper'))
      .filter((p) => p.offsetParent !== null)
      .map((p) => p.textContent.trim())
      .join('|')
  )
  note('hovering a row action reveals its name in a tooltip', actionTip.includes('详情'), `tooltip=${actionTip}`)
  await shot('4b-action-tooltip')

  // --- open the batch and move a sample into it ----------------------------
  if (!(await clickAct('detail'))) throw new Error('could not open the batch drawer')
  await wait(1500)
  await shot('5-batch-drawer')

  const drawerTitle = await page.$eval('.el-drawer__title', (e) => e.textContent.trim()).catch(() => '')
  note('the batch detail drawer opens', drawerTitle.includes('物流批次'), drawerTitle)

  if (!(await clickText('添加样品', '.el-drawer'))) throw new Error('could not open the add-samples dialog')
  await wait(1000)

  // tick the first available sample
  const checked = await page.evaluate(() => {
    const dialog = document.querySelector('.el-dialog')
    if (!dialog) return false
    const box = dialog.querySelector('.el-table__body .el-checkbox')
    if (!box) return false
    box.click()
    return true
  })
  await wait(400)
  await shot('6-add-samples')

  const confirmLabel = await page
    .$eval('.el-dialog .el-button--primary', (e) => e.textContent.trim())
    .catch(() => '')
  note('the add dialog reports how many samples are selected', confirmLabel.includes('1'), confirmLabel)

  await clickText('加入所选样品', '.el-dialog')
  await wait(2200)
  await shot('7-sample-added')

  const batchSampleRows = await page.$$eval('.el-drawer .el-table__row', (rows) =>
    rows.map((r) => r.textContent.trim())
  )
  note(
    'the sample now counts as part of the batch',
    batchSampleRows.some((t) => /S\d{9}/.test(t)),
    batchSampleRows.length + ' rows in the drawer'
  )

  const flagged = await page.$$eval('.el-drawer .el-table__row', (rows) => rows.length)
  note('the batch detail lists exactly one sample', flagged === 1, `rows=${flagged}`)
} catch (err) {
  note('detail page run', false, err.message)
  try {
    await shot('error')
  } catch {
    /* ignore */
  }
} finally {
  await context.close().catch(() => {})
  await browser.close()
}

fs.writeFileSync(path.join(outDir, 'detail_report.json'), JSON.stringify({ complaint, steps }, null, 2))
const failed = steps.filter((s) => !s.ok).length
console.log('')
console.log(`  RESULT : ${failed === 0 ? 'PASS' : 'FAIL (' + failed + ')'}   complaint=${complaint}`)
if (failed !== 0) process.exit(1)
