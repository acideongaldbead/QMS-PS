/**
 * d6.mjs
 *
 * Drives the D6 tab in a real browser: expand a corrective action, record an
 * effective verification (status -> verified), record an ineffective one
 * (status -> back for rework), then delete a verification and confirm the
 * history shrinks.
 *
 * The complaint, its root cause and one corrective action are created by
 * ui-d6.ps1 via the API before this runs; D6 has nothing to verify otherwise.
 *
 * Usage:
 *   node d6.mjs --complaint=C202600001 --out=<dir> --edge=<path>
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

function isoToday() {
  const d = new Date()
  return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`
}

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
      const els = Array.from(root.querySelectorAll('button, .el-tabs__item, .el-button'))
      // A fixed column is rendered twice; the hidden clone has no offsetParent.
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

/** Radios are not buttons, so clickText misses them; match the label exactly. */
async function clickRadio(text, scope = '.el-dialog') {
  const ok = await page.evaluate(
    (t, s) => {
      const root = document.querySelector(s) || document.body
      const el = Array.from(root.querySelectorAll('.el-radio')).find((r) => r.textContent.trim() === t)
      if (!el) return false
      el.click()
      return true
    },
    text,
    scope
  )
  await wait(300)
  return ok
}

async function typeByPlaceholder(placeholder, value, scope = '.el-dialog') {
  const input = await page.$(`${scope} input[placeholder="${placeholder}"], ${scope} textarea[placeholder="${placeholder}"]`)
  if (!input) throw new Error(`no field with placeholder "${placeholder}" in ${scope}`)
  await input.click({ clickCount: 3 })
  await input.type(String(value))
}

async function setDateByLabel(label, iso) {
  const focused = await page.evaluate((labelText) => {
    const norm = (s) => (s || '').replace(/[\s:：]/g, '')
    const item = Array.from(document.querySelectorAll('.el-form-item')).find((it) => {
      const lab = it.querySelector('.el-form-item__label')
      return lab && norm(lab.textContent) === labelText
    })
    if (!item) return false
    const input = item.querySelector('input')
    if (!input) return false
    input.focus()
    input.click()
    return true
  }, label)
  if (!focused) throw new Error(`no date field for "${label}"`)
  await page.keyboard.type(iso)
  await wait(300)
  await page.keyboard.press('Enter')
  await wait(400)
}

async function confirmMessageBox() {
  const ok = await page.evaluate(() => {
    const box = document.querySelector('.el-message-box')
    if (!box) return false
    const btn =
      box.querySelector('.el-message-box__btns .el-button--primary') ||
      Array.from(box.querySelectorAll('button')).find((b) => b.textContent.includes('确定'))
    if (!btn) return false
    btn.click()
    return true
  })
  await wait(800)
  return ok
}

/** The outer actions table keeps one expandable row; open it if it is closed. */
async function ensureExpanded() {
  const state = await page.evaluate(() => {
    const icon = document.querySelector('.el-table__expand-icon')
    if (!icon) return 'none'
    return icon.classList.contains('el-table__expand-icon--expanded') ? 'expanded' : 'collapsed'
  })
  if (state === 'none') throw new Error('no expandable corrective-action row')
  if (state === 'collapsed') {
    await page.evaluate(() => document.querySelector('.el-table__expand-icon').click())
    await wait(1000)
  }
}

/** Data rows of the verification table inside the expanded body. */
function verificationRowCount() {
  return page.evaluate(() => {
    const body = document.querySelector('.expand-body')
    if (!body) return -1
    const table = body.querySelector('.el-table')
    return table ? table.querySelectorAll('.el-table__row').length : -1
  })
}

async function shot(name) {
  await page.screenshot({ path: path.join(outDir, `d6-${name}.png`) })
}

try {
  // --- sign in and open the D6 tab -----------------------------------------
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

  if (!(await clickText('D6 措施实施与验证'))) throw new Error('could not open the D6 tab')
  await wait(1500)
  await shot('1-tab')

  const tabText = await page.evaluate(() => document.body.innerText)
  note('the D6 panel opens', tabText.includes('负责人在此反馈'), 'panel hint missing')

  // --- expand the action ----------------------------------------------------
  await ensureExpanded()
  await shot('2-expanded')
  const recordBtn = await page.evaluate(() =>
    Array.from(document.querySelectorAll('button')).some((b) => b.textContent.includes('记录验证'))
  )
  note('the row expands to its verification area', recordBtn, 'no record button after expanding')

  // --- record an effective verification ------------------------------------
  if (!(await clickText('记录验证'))) throw new Error('no record-verification button')
  await wait(700)
  await setDateByLabel('实际完成日期', isoToday())
  await typeByPlaceholder('实施情况、验证方式与结论', 'Checklist revised and two changeovers verified.')
  if (!(await clickRadio('有效'))) throw new Error('no "effective" radio')
  await shot('3-dialog-effective')
  if (!(await clickText('保存', '.el-dialog'))) throw new Error('no save button in the verification dialog')
  await wait(2500)
  await shot('4-effective')

  let body = await page.evaluate(() => document.body.innerText)
  note('an effective verdict marks the action verified', body.includes('已验证'), 'status did not become verified')
  await ensureExpanded()
  note('the verification is listed', (await verificationRowCount()) === 1, `rows=${await verificationRowCount()}`)

  // --- record an ineffective verification (rework branch) -------------------
  if (!(await clickText('记录验证'))) throw new Error('no record-verification button on the second pass')
  await wait(700)
  await typeByPlaceholder('实施情况、验证方式与结论', 'The drift recurred on the next changeover.')
  if (!(await clickRadio('无效，需返工'))) throw new Error('no "ineffective" radio')
  if (!(await clickText('保存', '.el-dialog'))) throw new Error('no save button on the second verification')
  await wait(2500)
  await shot('5-ineffective')

  body = await page.evaluate(() => document.body.innerText)
  note('an ineffective verdict sends the action back for rework', body.includes('验证不通过'), 'status did not become failed')
  await ensureExpanded()
  note('both verifications are kept as history', (await verificationRowCount()) === 2, `rows=${await verificationRowCount()}`)

  // --- delete one verification ---------------------------------------------
  if (!(await clickAct('delete'))) throw new Error('no delete action on a verification row')
  await wait(700)
  if (!(await confirmMessageBox())) throw new Error('the delete confirmation did not appear')
  await wait(1500)
  await shot('6-deleted')

  await ensureExpanded()
  note('deleting a verification shrinks the history', (await verificationRowCount()) === 1, `rows=${await verificationRowCount()}`)
} catch (err) {
  note('D6 page run', false, err.message)
  try {
    await shot('error')
  } catch {
    /* ignore */
  }
} finally {
  await context.close().catch(() => {})
  await browser.close()
}

fs.writeFileSync(path.join(outDir, 'd6_report.json'), JSON.stringify({ complaint, steps }, null, 2))
const failed = steps.filter((s) => !s.ok).length
console.log('')
console.log(`  RESULT : ${failed === 0 ? 'PASS' : 'FAIL (' + failed + ')'}   complaint=${complaint}`)
if (failed !== 0) process.exit(1)
