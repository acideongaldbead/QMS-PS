/**
 * d8.mjs
 *
 * Drives the whole D8 flow in a real browser, with each step done by the role
 * that owns it - the same sequence the business follows:
 *
 *   quality engineer  generate the report, hand it to an approver
 *   sales quality     find the send blocked while it awaits approval
 *   auditor            approve it
 *   sales quality     export the Word file, send it, and close the complaint
 *
 * The complaint is seeded to a report-ready D7 by ui-d8.ps1 via the API.
 *
 * Usage:
 *   node d8.mjs --complaint=C202600001 --out=<dir> --edge=<path>
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
const password = argv.password ?? 'Qms@2026'

const engineer = argv.engineer ?? 'siyuan.li'
const sales = argv.sales ?? 'xiaoran.ma'
const approver = argv.approver ?? 'hong.zhang'
/** The approver's display name, as seeded by V9 for U09 (report:approve). */
const APPROVER_NAME = '张宏'

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

const steps = []
function note(name, ok, detail = '') {
  steps.push({ name, ok, detail })
  console.log(`  ${ok ? 'PASS' : 'FAIL'}  ${name}${!ok && detail ? '  -> ' + detail : ''}`)
}

const wait = (ms) => new Promise((r) => setTimeout(r, ms))

let context = null
let page = null
let exportResponse = null
let pdfResponse = null

/** Every step runs in its own browser context, so the tokens cannot bleed. */
async function signIn(username) {
  if (context) {
    await context.close().catch(() => {})
  }
  context = browser.createBrowserContext
    ? await browser.createBrowserContext()
    : await browser.createIncognitoBrowserContext()
  page = await context.newPage()
  await page.setViewport({ width: 1680, height: 1080 })
  page.on('response', (res) => {
    if (res.url().includes('/export.docx')) {
      exportResponse = { status: res.status(), type: res.headers()['content-type'] || '' }
    }
    if (res.url().includes('/export.pdf')) {
      pdfResponse = { status: res.status(), type: res.headers()['content-type'] || '' }
    }
  })

  await page.goto(`${base}/#/login`, { waitUntil: 'networkidle2', timeout: 40000 })
  await page.evaluate(() => localStorage.clear())
  await page.reload({ waitUntil: 'networkidle2' })
  await page.waitForSelector('input[type="text"]', { timeout: 20000 })
  await page.type('input[type="text"]', username)
  await page.type('input[type="password"]', password)
  await page.click('button[type="submit"]')
  await page.waitForFunction(() => !!document.querySelector('.app-sidebar .nav-item'), { timeout: 25000 })
}

async function openD8Tab() {
  await page.goto(`${base}/#/complaints/${complaint}`, { waitUntil: 'networkidle2', timeout: 40000 })
  await page.waitForSelector('.stage-bar', { timeout: 25000 })
  await wait(1200)
  if (!(await clickText('D8 报告与结案'))) throw new Error('could not open the D8 tab')
  await wait(1400)
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
      const els = Array.from(root.querySelectorAll('button, .el-tabs__item, .el-button, a, .el-radio'))
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

/** Picks an option in the nth visible el-select of a scope. */
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

async function confirmMessageBox() {
  const ok = await page.evaluate(() => {
    const box = document.querySelector('.el-message-box')
    if (!box) return false
    const btn =
      box.querySelector('.el-message-box__btns .el-button--primary') ||
      Array.from(box.querySelectorAll('button')).find((b) => b.textContent.includes('确认') || b.textContent.includes('确定'))
    if (!btn) return false
    btn.click()
    return true
  })
  await wait(900)
  return ok
}

async function shot(name) {
  await page.screenshot({ path: path.join(outDir, `d8-${name}.png`) })
}

/** The primary button in the send screen's header, to read its disabled state. */
async function sendButtonDisabled() {
  return page.evaluate(() => {
    const btn = Array.from(document.querySelectorAll('button')).find(
      (b) => b.textContent.includes('发送报告') && b.classList.contains('el-button--primary')
    )
    return btn ? btn.disabled : null
  })
}

try {
  // --- 1. the quality engineer generates the report and submits it ----------
  await signIn(engineer)
  await openD8Tab()
  await shot('1-tab')

  const tabText = await page.evaluate(() => document.body.innerText)
  note('the D8 panel opens', tabText.includes('XTE-0071'), 'panel hint missing')

  if (!(await clickText('生成报告'))) throw new Error('no generate button')
  await wait(800)
  if (!(await clickText('生成', '.el-dialog'))) throw new Error('no confirm button in the generate dialog')
  await wait(2500)
  await shot('2-generated')

  const afterGen = await page.evaluate(() => document.body.innerText)
  const idMatch = afterGen.match(/R\d{9}/)
  note('the report is generated and listed', !!idMatch, 'no report id on the page')
  const reportId = idMatch ? idMatch[0] : null

  if (!(await clickAct('submit'))) throw new Error('no submit-for-approval action')
  await wait(900)
  await pickSelectIn('.el-dialog', 0, APPROVER_NAME)
  await shot('3-submit-dialog')
  if (!(await clickText('提交', '.el-dialog'))) throw new Error('no confirm button in the submit dialog')
  await wait(2200)

  const afterSubmit = await page.evaluate(() => document.body.innerText)
  note('the report goes into approval', afterSubmit.includes('审批中'), 'no pending tag on the row')
  note('the row names the approver', afterSubmit.includes(APPROVER_NAME), 'approver name missing')

  // --- 2. sales quality finds the send blocked ------------------------------
  await signIn(sales)
  await openD8Tab()
  // The send action stays visible but disabled until the report is approved, so
  // the owner can see what is missing rather than wonder where the button went.
  const sendDisabled = await page.evaluate(() => {
    const el = Array.from(document.querySelectorAll('[data-act="send"]')).find(
      (e) => e.offsetParent !== null
    )
    return el ? el.disabled : null
  })
  note('an unapproved report disables the send action', sendDisabled === true, `send disabled=${sendDisabled}`)
  await shot('4-blocked')

  if (!(await clickAct('viewReport'))) throw new Error('no view-report link')
  await wait(2000)
  await shot('5-report')
  const reportText = await page.evaluate(() => document.body.innerText)
  note(
    'the report page shows the 8D sections',
    reportText.includes('TECHNICAL REPORT') && reportText.includes('D1') && reportText.includes('D8'),
    'report sections missing'
  )

  // The Word export happens before the send: it is the file that goes out.
  if (!(await clickText('导出 Word'))) throw new Error('no export button')
  for (let i = 0; i < 20 && !exportResponse; i++) {
    await wait(500)
  }
  note(
    'the Word export returns a real .docx',
    !!exportResponse && exportResponse.status === 200 && exportResponse.type.includes('wordprocessingml'),
    exportResponse ? `status=${exportResponse.status} type=${exportResponse.type}` : 'no export response seen'
  )

  if (!(await clickText('导出 PDF'))) throw new Error('no PDF export button')
  for (let i = 0; i < 20 && !pdfResponse; i++) {
    await wait(500)
  }
  note(
    'the PDF export returns a real PDF',
    !!pdfResponse && pdfResponse.status === 200 && pdfResponse.type.includes('application/pdf'),
    pdfResponse ? `status=${pdfResponse.status} type=${pdfResponse.type}` : 'no pdf response seen'
  )

  if (!(await clickText('发送报告'))) throw new Error('no send link on the report page')
  await wait(2000)
  await shot('6-send-blocked')
  const blockedText = await page.evaluate(() => document.body.innerText)
  note('the send screen warns the report is not approved yet', blockedText.includes('尚未通过审批'))
  note('the send button is disabled while it awaits approval', (await sendButtonDisabled()) === true)

  // --- 3. the named approver approves --------------------------------------
  await signIn(approver)
  await openD8Tab()
  await shot('7-approver')
  if (!(await clickAct('approve'))) throw new Error('the approver has no approve action')
  await wait(900)
  const approveDialog = await page.evaluate(() => document.body.innerText)
  note('the approval dialog asks for a decision', approveDialog.includes('审批结论'))
  await shot('8-approve-dialog')
  if (!(await clickText('提交结论', '.el-dialog'))) throw new Error('no confirm button in the approval dialog')
  await wait(2200)

  const afterApprove = await page.evaluate(() => document.body.innerText)
  note('the report is approved', afterApprove.includes('已批准'), 'no approved tag on the row')
  await shot('9-approved')

  // --- 4. sales quality sends it and the complaint closes -------------------
  await signIn(sales)
  await openD8Tab()
  // The report page is reached through the row action; the send link lives there.
  if (!(await clickAct('viewReport'))) throw new Error('no view-report link after approval')
  await wait(1800)
  if (!(await clickText('发送报告'))) throw new Error('no send link on the report page')
  await wait(2000)
  await shot('10-send')
  const sendText = await page.evaluate(() => document.body.innerText)
  note('the send screen pre-fills the recipient and message', sendText.includes('发送前校验'), 'send form missing')
  note('the send button is enabled once approved', (await sendButtonDisabled()) === false)

  if (!(await clickText('发送报告'))) throw new Error('no send button')
  await wait(700)
  if (!(await confirmMessageBox())) throw new Error('the send confirmation did not appear')
  await wait(3000)
  await shot('11-sent')

  const afterSend = await page.evaluate(() => document.body.innerText)
  note('the communication log is recorded', /沟通记录（[1-9]/.test(afterSend) || afterSend.includes('报告已发送'), 'no send confirmation')

  await page.goto(`${base}/#/complaints/${complaint}`, { waitUntil: 'networkidle2', timeout: 40000 })
  await page.waitForSelector('.stage-bar', { timeout: 25000 })
  await wait(1200)
  const detailText = await page.evaluate(() => document.body.innerText)
  note('sending closes the complaint', detailText.includes('已结案'), 'no closed badge')

  // The process log should now carry the whole story of this report.
  if (!(await clickText('沟通与流程日志'))) throw new Error('no log tab')
  await wait(1600)
  await shot('12-log')
  const logText = await page.evaluate(() => document.body.innerText)
  note('the process log records the approval', logText.includes('审批'), 'no approval line in the log')
  note('the process log records the send', logText.includes('发送给客户'), 'no send line in the log')
} catch (err) {
  note('D8 page run', false, err.message)
  try {
    await shot('error')
  } catch {
    /* ignore */
  }
} finally {
  if (context) await context.close().catch(() => {})
  await browser.close()
}

fs.writeFileSync(path.join(outDir, 'd8_report.json'), JSON.stringify({ complaint, steps }, null, 2))
const failed = steps.filter((s) => !s.ok).length
console.log('')
console.log(`  RESULT : ${failed === 0 ? 'PASS' : 'FAIL (' + failed + ')'}   complaint=${complaint}`)
if (failed !== 0) process.exit(1)
