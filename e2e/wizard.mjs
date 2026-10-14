/**
 * wizard.mjs
 *
 * Drives the registration wizard in a real browser: fills all five steps,
 * submits, and reports the resulting complaint id. This is the end-to-end proof
 * that the UI wires to the API correctly, which API-level tests alone cannot show.
 *
 * Element Plus renders its dropdowns into a teleported popper, so options are
 * picked by clicking the visible panel rather than by DOM nesting.
 *
 * Usage:
 *   node wizard.mjs --out=<dir> --edge=<path> [--base=http://localhost:8080]
 *                   [--user=xiaoran.ma] [--password=Qms@2026] [--keep]
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
const user = argv.user ?? 'xiaoran.ma'
const password = argv.password ?? 'Qms@2026'

if (!edge) {
  console.error('missing --edge=<path to msedge.exe>')
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

/** Picks an option in the nth visible .el-select by matching its label text. */
async function pickSelect(index, textFragment) {
  const selects = await page.$$('.el-select')
  if (index >= selects.length) throw new Error(`select #${index} not found (have ${selects.length})`)
  await selects[index].click()
  await wait(350)
  const clicked = await page.evaluate((fragment) => {
    const panels = Array.from(document.querySelectorAll('.el-select-dropdown')).filter(
      (d) => d.offsetParent !== null
    )
    const items = panels.flatMap((p) => Array.from(p.querySelectorAll('.el-select-dropdown__item')))
    const target =
      items.find((i) => i.textContent.trim() === fragment) ??
      items.find((i) => i.textContent.includes(fragment))
    if (!target) return false
    target.click()
    return true
  }, textFragment)
  await wait(300)
  if (!clicked) throw new Error(`option containing "${textFragment}" not found`)
}

/** Types into the nth date editor and commits it. */
async function pickDate(index, isoDate) {
  const editors = await page.$$('.el-date-editor input')
  if (index >= editors.length) throw new Error(`date editor #${index} not found`)
  await editors[index].click()
  await wait(200)
  await editors[index].type(isoDate)
  await wait(300)
  await page.keyboard.press('Enter')
  await wait(300)
  await page.keyboard.press('Escape')
  await wait(200)
}

async function shot(name) {
  const file = path.join(outDir, `wizard-${name}.png`)
  await page.screenshot({ path: file })
  return file
}

async function clickButton(text) {
  const ok = await page.evaluate((t) => {
    const buttons = Array.from(document.querySelectorAll('button'))
    // offsetParent filters out the hidden duplicate Element renders for a table's
    // fixed columns; clicking that clone does nothing.
    const target = buttons.find(
      (b) => (b.textContent.trim() === t || b.textContent.trim().includes(t)) && b.offsetParent !== null
    )
    if (!target) return false
    target.click()
    return true
  }, text)
  await wait(500)
  if (!ok) throw new Error(`button "${text}" not found`)
}

function isoDaysFromNow(days) {
  const d = new Date()
  d.setDate(d.getDate() + days)
  return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`
}

let complaintId = null
try {
  // --- sign in ---------------------------------------------------------------
  await page.goto(`${base}/#/login`, { waitUntil: 'networkidle2', timeout: 40000 })
  await page.evaluate(() => localStorage.clear())
  await page.reload({ waitUntil: 'networkidle2' })
  await page.waitForSelector('input[type="text"]', { timeout: 20000 })
  await page.type('input[type="text"]', user)
  await page.type('input[type="password"]', password)
  await page.click('button[type="submit"]')
  await page.waitForFunction(() => !!document.querySelector('.app-sidebar .nav-item'), { timeout: 25000 })
  note('signed in', true, user)

  // --- open the wizard -------------------------------------------------------
  await page.goto(`${base}/#/complaints/new`, { waitUntil: 'networkidle2', timeout: 40000 })
  await page.waitForSelector('.el-steps', { timeout: 20000 })
  await wait(900)
  await shot('1-header-empty')

  const stepCount = await page.$$eval('.el-step', (els) => els.length)
  note('wizard shows five steps', stepCount === 5, `count=${stepCount}`)

  // --- step 1: header --------------------------------------------------------
  await pickSelect(0, '技术投诉')
  await pickSelect(1, '非常紧急')
  await pickSelect(2, '客户端装配')
  await pickSelect(3, '刘丹茜')
  await pickSelect(4, '马晓然')
  await pickDate(0, isoDaysFromNow(30))

  const preview = await page.$eval('.date-preview', (el) => el.textContent.replace(/\s+/g, ' ').trim())
  const haveStart = /开始 \d{4}-\d{2}-\d{2}/.test(preview)
  const haveTarget = /目标 \d{4}-\d{2}-\d{2}/.test(preview)
  note('start date was previewed from the default rule', haveStart, preview)
  note('target date was previewed from the priority rule', haveTarget, preview)

  await shot('2-header-filled')
  await clickButton('下一步')

  // --- step 2: quality partner ----------------------------------------------
  await wait(600)
  await pickSelect(0, '博世')
  await wait(900) // contacts and ship-to load for the chosen customer
  await pickSelect(1, '张伟')
  await pickSelect(2, '通用武汉工厂')
  await pickSelect(3, '动力总成')

  const contactCount = await page.evaluate(() => {
    const selects = document.querySelectorAll('.el-select')
    return selects.length
  })
  note('quality partner step rendered', contactCount >= 4, `selects=${contactCount}`)
  await shot('3-partner-filled')
  await clickButton('下一步')

  // --- step 3: product -------------------------------------------------------
  await wait(600)
  await pickSelect(0, '12NC-934068123456')
  await wait(700) // product master pre-fills type and packing
  const productTypeText = await page.evaluate(() => {
    const s = document.querySelectorAll('.el-select')[1]
    return s ? s.textContent.trim() : ''
  })
  note('product master pre-filled the product type', productTypeText.includes('MOSFET'), productTypeText)
  await shot('4-product-filled')
  await clickButton('下一步')

  // --- step 4: failure description ------------------------------------------
  await wait(600)
  await pickSelect(0, '封装崩边')
  await shot('5-failure-filled')
  await clickButton('下一步')

  // --- step 5: samples -------------------------------------------------------
  await wait(600)
  await pickSelect(1, 'Assembly related')
  await wait(300)
  await pickSelect(2, 'Molding')
  await wait(300)
  await pickSelect(3, 'Package chipping')
  await shot('6-sample-filled')

  const chain = await page.evaluate(() => {
    const selects = document.querySelectorAll('.el-select')
    return Array.from(selects)
      .slice(1, 4)
      .map((s) => s.textContent.trim())
      .join(' | ')
  })
  note('three-level failure type cascade is selectable', chain.includes('Package chipping'), chain)

  // --- submit ----------------------------------------------------------------
  await clickButton('提交登记')
  await wait(2500)
  await shot('7-result')

  const resultText = await page.evaluate(() => document.body.innerText)
  const match = resultText.match(/C\d{9}/)
  complaintId = match ? match[0] : null
  note('registration completed and an id was shown', !!complaintId, complaintId ?? 'no id found')

  const showsDates = /开始日期/.test(resultText) && /目标日期/.test(resultText)
  note('result panel shows the stored dates', showsDates)

  const showsCustomer = /博世/.test(resultText)
  note('result panel shows the resolved customer name', showsCustomer)

  // --- attachments -----------------------------------------------------------
  // The panel only exists once the complaint has an id, which is why files are
  // attached after registration rather than during the wizard.
  const uploadInput = await page.$('.el-upload input[type="file"]')
  note('the attachment upload control is present', !!uploadInput)

  if (uploadInput) {
    const pngPath = path.join(outDir, 'wizard-attachment.png')
    fs.writeFileSync(
      pngPath,
      Buffer.from(
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8DwHwAFAAH/q842iQAAAABJRU5ErkJggg==',
        'base64'
      )
    )
    await uploadInput.uploadFile(pngPath)
    await wait(2200)
    await shot('8-attachment-uploaded')

    const listedNames = await page.$$eval('.el-table__row td:first-child', (els) =>
      els.map((e) => e.textContent.trim())
    )
    note(
      'the uploaded file appears in the attachment list',
      listedNames.includes('wizard-attachment.png'),
      listedNames.join(', ')
    )

    // A Windows executable renamed to .pdf: the extension is allowed, the content
    // is not, and the UI must refuse it.
    const disguisedPath = path.join(outDir, 'wizard-notreally.pdf')
    fs.writeFileSync(
      disguisedPath,
      Buffer.concat([Buffer.from([0x4d, 0x5a, 0x90, 0x00, 0x03, 0x00, 0x00, 0x00]), Buffer.alloc(4096)])
    )
    const secondInput = await page.$('.el-upload input[type="file"]')
    await secondInput.uploadFile(disguisedPath)
    await wait(2200)
    await shot('9-attachment-refused')

    const messages = await page.evaluate(() =>
      Array.from(document.querySelectorAll('.el-message'))
        .map((m) => m.textContent.trim())
        .join(' | ')
    )
    note(
      'a disguised executable is refused with an explanation',
      /可执行程序|不一致/.test(messages),
      messages || '(no toast shown)'
    )

    const namesAfterRefusal = await page.$$eval('.el-table__row td:first-child', (els) =>
      els.map((e) => e.textContent.trim())
    )
    note(
      'the refused file is not listed',
      !namesAfterRefusal.includes('wizard-notreally.pdf'),
      namesAfterRefusal.join(', ')
    )
  }
} catch (err) {
  note('wizard run', false, err.message)
  try {
    await shot('error')
  } catch {
    /* ignore */
  }
} finally {
  if (!complaintId) {
    steps.push({ name: 'no complaint created', ok: true, detail: 'nothing to clean up' })
  }
  await context.close().catch(() => {})
  await browser.close()
}

fs.writeFileSync(path.join(outDir, 'wizard_report.json'), JSON.stringify({ complaintId, steps }, null, 2))
const failed = steps.filter((s) => !s.ok).length
console.log('')
console.log(`  RESULT : ${failed === 0 ? 'PASS' : 'FAIL (' + failed + ')'}   created=${complaintId}`)
if (failed !== 0) process.exit(1)
