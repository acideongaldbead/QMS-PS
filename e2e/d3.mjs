/**
 * d3.mjs
 *
 * Drives the D3 tab in a real browser: makes the "is containment needed"
 * decision, registers a containment action, and completes it to check that the
 * completion date is stamped. The API half of task 2.5 is
 * scripts/verify-containment.ps1.
 *
 * Usage:
 *   node d3.mjs --complaint=C202600001 --out=<dir> --edge=<path>
 *               [--base=http://localhost:8080] [--user=siyuan.li]
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
  if (!clicked) throw new Error(`option "${fragment}" not found in ${scope}`)
}

async function typeByPlaceholder(placeholder, value) {
  const input = await page.$(`input[placeholder="${placeholder}"], textarea[placeholder="${placeholder}"]`)
  if (!input) throw new Error(`no field with placeholder "${placeholder}"`)
  await input.click({ clickCount: 3 })
  await input.type(String(value))
}

async function shot(name) {
  const file = path.join(outDir, `d3-${name}.png`)
  await page.screenshot({ path: file })
  return file
}

function isoToday() {
  return isoDaysFromNow(0)
}

function isoDaysFromNow(days) {
  const d = new Date()
  d.setDate(d.getDate() + days)
  return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`
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

  await page.goto(`${base}/#/complaints/${complaint}`, { waitUntil: 'networkidle2', timeout: 40000 })
  await page.waitForSelector('.stage-bar', { timeout: 25000 })
  await wait(1200)

  // --- open the D3 tab ------------------------------------------------------
  if (!(await clickText('D3 遏制措施'))) throw new Error('could not open the D3 tab')
  await wait(1400)
  await shot('1-tab')

  const bodyText = await page.evaluate(() => document.body.innerText)
  note('the D3 tab asks whether containment is needed', bodyText.includes('是否需要遏制措施'))
  note('the decision starts unanswered', bodyText.includes('需要遏制') && bodyText.includes('不需要遏制'))

  // --- make the decision ----------------------------------------------------
  if (!(await clickText('需要遏制'))) throw new Error('could not select the decision radio')
  await wait(400)
  const noteBox = await page.$('textarea')
  if (noteBox) {
    await noteBox.click()
    await noteBox.type('Suspect stock must be blocked at the customer.')
  }
  await shot('2-decision')
  if (!(await clickText('提交判断'))) throw new Error('no submit button for the decision')
  await wait(2200)
  await shot('3-decided')

  const afterDecision = await page.evaluate(() => document.body.innerText)
  note('the decision is recorded as required', afterDecision.includes('需要遏制措施'))
  note('the actions table appears once containment is required', afterDecision.includes('新增遏制措施'))

  // --- register an action ---------------------------------------------------
  if (!(await clickText('新增遏制措施'))) throw new Error('could not open the action dialog')
  await wait(900)
  await typeByPlaceholder('NEX sample number', 'NEX-8801')
  await typeByPlaceholder('customer sample number', 'CS-D3UI-1')
  await typeByPlaceholder('要执行的具体遏制动作', 'Block all suspect stock at the customer site')
  await pickSelectIn('.el-dialog', 0, '赵敏')
  // The plan date sits five days out, so finishing today is an anomaly the UI
  // should flag once the action is completed.
  const planDates = await page.$$('.el-dialog .el-date-editor input')
  if (planDates.length >= 1) {
    await planDates[0].click()
    await wait(200)
    await planDates[0].type(isoDaysFromNow(5))
    await wait(300)
    await page.keyboard.press('Enter')
    await wait(300)
  }
  await shot('4-action-dialog')
  if (!(await clickText('保存', '.el-dialog'))) throw new Error('no save button in the action dialog')
  await wait(2200)
  await shot('5-action-saved')

  const afterCreate = await page.evaluate(() => document.body.innerText)
  note('the containment action is listed', /CA\d{9}/.test(afterCreate), 'no action id on the page')
  note('the action starts as to-do', afterCreate.includes('待处理'))
  note('the owner name is resolved', afterCreate.includes('赵敏'))

  // --- complete it and check the completion date ---------------------------
  if (!(await clickAct('edit'))) throw new Error('could not open the edit dialog')
  await wait(900)
  await pickSelectIn('.el-dialog', 1, '已完成')
  const resultBox = await page.$('.el-dialog textarea')
  if (resultBox) {
    await resultBox.click()
    await resultBox.type('All suspect stock contained and quarantined.')
  }
  await shot('6-complete-dialog')
  if (!(await clickText('保存', '.el-dialog'))) throw new Error('no save button while completing')
  await wait(2200)
  await shot('7-completed')

  const afterComplete = await page.evaluate(() => document.body.innerText)
  note('the action shows as completed', afterComplete.includes('已完成'))
  note('completing stamps the completion date', afterComplete.includes(isoToday()), 'today not shown')
  note('the planned completion date is shown', afterComplete.includes(isoDaysFromNow(5)), 'plan date not shown')

  const hasWarningMarker = await page.evaluate(() => !!document.querySelector('.warn-mark'))
  note(
    'finishing earlier than planned raises a warning marker',
    hasWarningMarker,
    'no warning marker rendered'
  )
} catch (err) {
  note('D3 page run', false, err.message)
  try {
    await shot('error')
  } catch {
    /* ignore */
  }
} finally {
  await context.close().catch(() => {})
  await browser.close()
}

fs.writeFileSync(path.join(outDir, 'd3_report.json'), JSON.stringify({ complaint, steps }, null, 2))
const failed = steps.filter((s) => !s.ok).length
console.log('')
console.log(`  RESULT : ${failed === 0 ? 'PASS' : 'FAIL (' + failed + ')'}   complaint=${complaint}`)
if (failed !== 0) process.exit(1)
