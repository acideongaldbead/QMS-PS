/**
 * d7.mjs
 *
 * Drives the D7 tab in a real browser: register a file-update record through the
 * dialog, confirm it lists as "to update", edit its status to "completed", then
 * delete it and confirm the empty state returns.
 *
 * The complaint is created by ui-d7.ps1 via the API before this runs; D7 does not
 * require a root cause or action, so a bare complaint is enough.
 *
 * Usage:
 *   node d7.mjs --complaint=C202600001 --out=<dir> --edge=<path>
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

/** Element Plus renders an el-select as a wrapper plus a popper; open it, pick. */
async function selectByLabel(label, optionText, scope = '.el-dialog') {
  const opened = await page.evaluate(
    (labelText, s) => {
      const norm = (x) => (x || '').replace(/[\s:：]/g, '')
      const root = document.querySelector(s) || document.body
      const item = Array.from(root.querySelectorAll('.el-form-item')).find((it) => {
        const lab = it.querySelector('.el-form-item__label')
        return lab && norm(lab.textContent) === norm(labelText)
      })
      if (!item) return false
      const target = item.querySelector('.el-select__wrapper') || item.querySelector('.el-select')
      if (!target) return false
      target.click()
      return true
    },
    label,
    scope
  )
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

/** Focuses the input inside a labelled form item and types into it. */
async function typeByLabel(label, value, scope = '.el-dialog') {
  const ok = await page.evaluate(
    (labelText, s) => {
      const norm = (x) => (x || '').replace(/[\s:：]/g, '')
      const root = document.querySelector(s) || document.body
      const item = Array.from(root.querySelectorAll('.el-form-item')).find((it) => {
        const lab = it.querySelector('.el-form-item__label')
        return lab && norm(lab.textContent) === norm(labelText)
      })
      if (!item) return false
      const input = item.querySelector('input, textarea')
      if (!input) return false
      input.focus()
      return true
    },
    label,
    scope
  )
  if (!ok) throw new Error(`no input for label "${label}"`)
  await page.keyboard.type(String(value))
  await wait(200)
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
  await page.screenshot({ path: path.join(outDir, `d7-${name}.png`) })
}

try {
  // --- sign in and open the D7 tab -----------------------------------------
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

  if (!(await clickText('D7 预防再发生'))) throw new Error('could not open the D7 tab')
  await wait(1500)
  await shot('1-tab')

  const tabText = await page.evaluate(() => document.body.innerText)
  note('the D7 panel opens', tabText.includes('登记需更新的文件'), 'panel hint missing')

  // --- register a file update ----------------------------------------------
  if (!(await clickText('登记文件更新'))) throw new Error('could not open the prevention dialog')
  await wait(800)
  await selectByLabel('文件类型', 'FMEA')
  await typeByLabel('NEX 样品号', 'NEX-D7-1')
  await typeByLabel('参考编号', 'FMEA-8801')
  await shot('2-dialog')

  if (!(await clickText('保存', '.el-dialog'))) throw new Error('no save button in the prevention dialog')
  await wait(2500)
  await shot('3-created')

  const afterCreate = await page.evaluate(() => document.body.innerText)
  note('the file update is listed', afterCreate.includes('FMEA') && afterCreate.includes('FMEA-8801'), 'row missing')
  note('it starts as to-update', afterCreate.includes('待更新'), 'status tag missing')

  // --- edit the status to completed ----------------------------------------
  if (!(await clickAct('edit'))) throw new Error('could not open the edit dialog')
  await wait(800)
  await selectByLabel('状态', '已完成')
  if (!(await clickText('保存', '.el-dialog'))) throw new Error('no save button while editing')
  await wait(2500)
  await shot('4-edited')

  const afterEdit = await page.evaluate(() => document.body.innerText)
  note('the status change is stored', afterEdit.includes('已完成'), 'the new status is not shown')

  // --- delete it ------------------------------------------------------------
  if (!(await clickAct('delete'))) throw new Error('no delete action')
  await wait(700)
  if (!(await confirmMessageBox())) throw new Error('the delete confirmation did not appear')
  await wait(1500)
  await shot('5-deleted')

  const afterDelete = await page.evaluate(() => document.body.innerText)
  note('the record is gone', !afterDelete.includes('FMEA-8801'), 'the row is still listed')
  note('the empty state returns', afterDelete.includes('尚未登记预防文件'), 'no empty-state text')
} catch (err) {
  note('D7 page run', false, err.message)
  try {
    await shot('error')
  } catch {
    /* ignore */
  }
} finally {
  await context.close().catch(() => {})
  await browser.close()
}

fs.writeFileSync(path.join(outDir, 'd7_report.json'), JSON.stringify({ complaint, steps }, null, 2))
const failed = steps.filter((s) => !s.ok).length
console.log('')
console.log(`  RESULT : ${failed === 0 ? 'PASS' : 'FAIL (' + failed + ')'}   complaint=${complaint}`)
if (failed !== 0) process.exit(1)
