/**
 * d5.mjs
 *
 * Drives the D5 tab in a real browser: create a corrective action through the
 * dialog (root cause pre-selected, planned action, owner, target date), confirm
 * it lands in the list, edit it to "in progress", then delete it and confirm it
 * is gone.
 *
 * The complaint and the root cause it is based on are created by ui-d5.ps1 via
 * the API before this runs; D5 has nothing to attach to without a root cause.
 *
 * Usage:
 *   node d5.mjs --complaint=C202600001 --out=<dir> --edge=<path>
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

async function typeByPlaceholder(placeholder, value, scope = '.el-dialog') {
  const input = await page.$(`${scope} input[placeholder="${placeholder}"], ${scope} textarea[placeholder="${placeholder}"]`)
  if (!input) throw new Error(`no field with placeholder "${placeholder}" in ${scope}`)
  await input.click({ clickCount: 3 })
  await input.type(String(value))
}

/** Element Plus renders an el-select as a wrapper plus a popper; open it, pick. */
async function selectByLabel(label, optionText) {
  const opened = await page.evaluate((labelText) => {
    const norm = (s) => (s || '').replace(/[\s:：]/g, '')
    const item = Array.from(document.querySelectorAll('.el-form-item')).find((it) => {
      const lab = it.querySelector('.el-form-item__label')
      return lab && norm(lab.textContent) === labelText
    })
    if (!item) return false
    const target = item.querySelector('.el-select__wrapper') || item.querySelector('.el-select')
    if (!target) return false
    target.click()
    return true
  }, label)
  if (!opened) throw new Error(`no select for "${label}"`)
  await wait(500)

  const picked = await page.evaluate((t) => {
    const dropdowns = Array.from(document.querySelectorAll('.el-select-dropdown')).filter((d) => d.offsetParent !== null)
    for (const d of dropdowns) {
      const opt = Array.from(d.querySelectorAll('.el-select-dropdown__item')).find((li) => li.textContent.includes(t))
      if (opt) {
        opt.click()
        return true
      }
    }
    return false
  }, optionText)
  if (!picked) throw new Error(`no option "${optionText}" in the "${label}" dropdown`)
  await wait(400)
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

async function shot(name) {
  await page.screenshot({ path: path.join(outDir, `d5-${name}.png`) })
}

try {
  // --- sign in and open the D5 tab -----------------------------------------
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

  if (!(await clickText('D5 纠正措施'))) throw new Error('could not open the D5 tab')
  await wait(1500)
  await shot('1-tab')

  const tabText = await page.evaluate(() => document.body.innerText)
  note('the corrective-action panel opens', tabText.includes('纠正措施基于'), 'panel hint missing')

  // --- create a corrective action through the dialog -----------------------
  if (!(await clickText('新增纠正措施'))) throw new Error('could not open the corrective-action dialog')
  await wait(900)
  await typeByPlaceholder('要实施的永久纠正措施', 'Add a re-verification step to the changeover checklist.')
  await selectByLabel('责任人', '李思远')
  await setDateByLabel('目标日期', '2026-12-31')
  await shot('2-dialog')

  if (!(await clickText('保存', '.el-dialog'))) throw new Error('no save button in the corrective-action dialog')
  await wait(2500)
  await shot('3-created')

  const afterCreate = await page.evaluate(() => document.body.innerText)
  const idMatch = afterCreate.match(/PCA\d{9}/)
  note('the corrective action is listed', !!idMatch, 'no PCA id on the page')
  note('it starts as to-do', afterCreate.includes('待处理'), 'status tag missing')
  const actionId = idMatch ? idMatch[0] : null

  // --- edit it to "in progress" --------------------------------------------
  if (!(await clickText('编辑'))) throw new Error('could not open the edit dialog')
  await wait(900)
  await selectByLabel('状态', '进行中')
  if (!(await clickText('保存', '.el-dialog'))) throw new Error('no save button while editing')
  await wait(2500)
  await shot('4-edited')

  const afterEdit = await page.evaluate(() => document.body.innerText)
  note('the edit is stored', afterEdit.includes('进行中'), 'the new status is not shown')

  // --- delete it ------------------------------------------------------------
  if (!(await clickText('删除'))) throw new Error('no delete action')
  await wait(700)
  if (!(await confirmMessageBox())) throw new Error('the delete confirmation did not appear')
  await wait(1500)
  await shot('5-deleted')

  const afterDelete = await page.evaluate(() => document.body.innerText)
  const stillThere = actionId ? afterDelete.includes(actionId) : /PCA\d{9}/.test(afterDelete)
  note('the corrective action is gone', !stillThere, 'the row is still listed')
  note('the empty state returns', afterDelete.includes('尚未制定纠正措施'), 'no empty-state text')
} catch (err) {
  note('D5 page run', false, err.message)
  try {
    await shot('error')
  } catch {
    /* ignore */
  }
} finally {
  await context.close().catch(() => {})
  await browser.close()
}

fs.writeFileSync(path.join(outDir, 'd5_report.json'), JSON.stringify({ complaint, steps }, null, 2))
const failed = steps.filter((s) => !s.ok).length
console.log('')
console.log(`  RESULT : ${failed === 0 ? 'PASS' : 'FAIL (' + failed + ')'}   complaint=${complaint}`)
if (failed !== 0) process.exit(1)
