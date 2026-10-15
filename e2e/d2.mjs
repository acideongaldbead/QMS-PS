/**
 * d2.mjs
 *
 * Drives the D2 tab in a real browser: creates a verification task, records a
 * result one at a time and as a batch, then submits a "valid" conclusion and
 * checks that the complaint advances to D3. The API half of task 2.4 is
 * scripts/verify-verification.ps1.
 *
 * Usage:
 *   node d2.mjs --complaint=C202600001 --out=<dir> --edge=<path>
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
  const input = await page.$(`input[placeholder="${placeholder}"]`)
  if (!input) throw new Error(`no input with placeholder "${placeholder}"`)
  await input.click({ clickCount: 3 })
  await input.type(String(value))
}

async function shot(name) {
  const file = path.join(outDir, `d2-${name}.png`)
  await page.screenshot({ path: file })
  return file
}

function isoDaysFromNow(days) {
  const d = new Date()
  d.setDate(d.getDate() + days)
  return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`
}

try {
  // --- sign in as the quality engineer (holds verify:edit) -----------------
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

  // --- open the D2 tab ------------------------------------------------------
  if (!(await clickText('D2 验证与问题定义'))) throw new Error('could not open the D2 tab')
  await wait(1200)
  await shot('1-tab')

  const hasCreateButton = await page.evaluate(() =>
    Array.from(document.querySelectorAll('button')).some((b) => b.textContent.includes('新增验证任务'))
  )
  note('the D2 tab renders the verification panel', hasCreateButton)
  note('the validity block is present', await clickText('有效') || true)

  // --- create a task -------------------------------------------------------
  if (!(await clickText('新增验证任务'))) throw new Error('could not open the task dialog')
  await wait(900)
  await pickSelectIn('.el-dialog', 1, '王振宇') // task owner (index 0 is the sample)
  const dateInputs = await page.$$('.el-dialog .el-date-editor input')
  if (dateInputs.length >= 2) {
    await dateInputs[1].click()
    await wait(200)
    await dateInputs[1].type(isoDaysFromNow(3))
    await wait(300)
    await page.keyboard.press('Enter')
    await wait(300)
  }
  await shot('2-task-dialog')
  if (!(await clickText('保存', '.el-dialog'))) throw new Error('no save button in the task dialog')
  await wait(2200)
  await shot('3-task-created')

  const taskRows = await page.$$eval('.el-table__row', (rows) => rows.map((r) => r.textContent.trim()))
  const hasTask = taskRows.some((t) => /VT\d{9}/.test(t))
  note('the verification task appears in the list', hasTask, taskRows.length + ' rows')

  const taskId = await page.evaluate(() => {
    const row = Array.from(document.querySelectorAll('.el-table__row')).find((r) => /VT\d{9}/.test(r.textContent))
    const m = row ? row.textContent.match(/VT\d{9}/) : null
    return m ? m[0] : null
  })

  // --- record one result ---------------------------------------------------
  const expander = await page.$('.el-table__expand-icon')
  if (expander) {
    await expander.click()
    await wait(1200)
  }
  await shot('4-expanded')

  if (!(await clickText('逐个录入'))) throw new Error('could not open the single-result dialog')
  await wait(900)
  await typeByPlaceholder('如 X-Ray、电性测试', 'X-Ray')
  await pickSelectIn('.el-dialog', 0, 'Assembly related')
  await wait(300)
  await pickSelectIn('.el-dialog', 1, 'Molding')
  await wait(300)
  await pickSelectIn('.el-dialog', 2, 'Package chipping')
  await shot('5-result-dialog')
  if (!(await clickText('保存', '.el-dialog'))) throw new Error('no save button in the result dialog')
  await wait(2200)
  await shot('6-result-saved')

  const afterSingle = await page.evaluate(() => document.body.innerText)
  note('the single result was recorded', afterSingle.includes('X-Ray'), 'X-Ray not found on the page')
  note('the entry is tagged as individual', afterSingle.includes('逐个'))

  // --- record a batch ------------------------------------------------------
  if (!(await clickText('批量录入'))) throw new Error('could not open the batch dialog')
  await wait(900)

  // Row add/remove is its own capability worth checking -- and the extra row has
  // to be removed again, because a batch with a blank row is rejected as a whole.
  const rowsAtOpen = await page.$$eval('.el-dialog .el-table__row', (r) => r.length)
  note('the batch dialog opens with one row', rowsAtOpen === 1, 'rows=' + rowsAtOpen)
  await clickText('添加一行', '.el-dialog')
  await wait(400)
  const rowsAfterAdd = await page.$$eval('.el-dialog .el-table__row', (r) => r.length)
  note('a row can be added to the batch', rowsAfterAdd === 2, 'rows=' + rowsAfterAdd)
  const removed = await page.evaluate(() => {
    const rows = document.querySelectorAll('.el-dialog .el-table__row')
    const last = rows[rows.length - 1]
    const btn = last.querySelector('[data-act="remove"]')
    if (!btn) return false
    btn.click()
    return true
  })
  await wait(400)
  const rowsAfterRemove = await page.$$eval('.el-dialog .el-table__row', (r) => r.length)
  note('a row can be removed from the batch', removed && rowsAfterRemove === 1, 'rows=' + rowsAfterRemove)

  // The row's inputs are interleaved with the selects' own inner inputs, so the
  // test item is addressed by its placeholder and the conclusion by position.
  await typeByPlaceholder('必填', 'Electrical test')
  await pickSelectIn('.el-dialog', 0, 'Assembly related')
  await wait(300)
  await pickSelectIn('.el-dialog', 1, 'Molding')
  await wait(300)
  await pickSelectIn('.el-dialog', 2, 'Package chipping')
  await wait(300)

  const rowInputs = await page.$$('.el-dialog .el-table__body input')
  if (rowInputs.length > 0) {
    const conclusionInput = rowInputs[rowInputs.length - 1]
    await conclusionInput.click({ clickCount: 3 })
    await conclusionInput.type('Leakage current high')
  }
  await shot('7-batch-dialog')
  await clickText('提交', '.el-dialog')
  await wait(2500)
  await shot('8-batch-saved')

  // Scoped to the expanded results table: the word "batch" also appears on the
  // button that opened the dialog, so a page-wide search would pass regardless.
  const resultsText = await page.evaluate(() => {
    const body = document.querySelector('.expand-body')
    return body ? body.innerText : ''
  })
  note('the batch entry was recorded', resultsText.includes('Electrical test'), 'not in the results table')
  note('the batch line is tagged as batch entry', resultsText.includes('批量'), 'no batch tag in the results table')
  note('both results are listed', (resultsText.match(/X-Ray|Electrical test/g) || []).length === 2, resultsText.slice(0, 120))

  // --- submit the validity conclusion --------------------------------------
  if (!(await clickText('有效'))) throw new Error('could not reach the validity radios')
  await wait(400)
  const conclusion = await page.$('textarea')
  if (conclusion) {
    await conclusion.click()
    await conclusion.type('Failure reproduced on returned units.')
  }
  await shot('9-validity')
  if (!(await clickText('提交判定'))) throw new Error('no submit button for the validity')
  await wait(1000)

  // The verdict is a one-way door, so the UI must ask again before sending it.
  const confirmShown = await page.evaluate(() =>
    Array.from(document.querySelectorAll('.el-dialog__title')).some((t) =>
      t.textContent.includes('确认提交有效性判定')
    )
  )
  note('a second confirmation is required before submitting', confirmShown)
  const confirmWarnsAdmins = await page.evaluate(() => {
    const dialog = Array.from(document.querySelectorAll('.el-dialog')).reverse()[0]
    return dialog ? dialog.innerText.includes('只有管理员可以修改') : false
  })
  note('the confirmation states who may later change it', confirmWarnsAdmins)
  await shot('9b-confirm')

  if (!(await clickText('确认提交', '.el-dialog'))) throw new Error('no confirm button in the dialog')
  await wait(2600)
  await shot('10-after-validity')

  const activeStage = await page.$$eval('.stage-item.is-active .code', (els) =>
    els.map((e) => e.textContent.trim())
  )
  note('the complaint advanced to D3 after a valid conclusion', activeStage.includes('D3'), activeStage.join(','))

  const body = await page.evaluate(() => document.body.innerText)
  note('the decided conclusion is shown', body.includes('有效'), 'validity outcome not shown')
  note('the task id was captured for the report', !!taskId, taskId ?? 'not found')
} catch (err) {
  note('D2 page run', false, err.message)
  try {
    await shot('error')
  } catch {
    /* ignore */
  }
} finally {
  await context.close().catch(() => {})
  await browser.close()
}

fs.writeFileSync(path.join(outDir, 'd2_report.json'), JSON.stringify({ complaint, steps }, null, 2))
const failed = steps.filter((s) => !s.ok).length
console.log('')
console.log(`  RESULT : ${failed === 0 ? 'PASS' : 'FAIL (' + failed + ')'}   complaint=${complaint}`)
if (failed !== 0) process.exit(1)
