/**
 * announcement.mjs
 *
 * Drives the announcement management screen (requirement 3.0 / PS-003) in a real
 * browser: the administrator authors a formatted announcement in the rich-text
 * editor, publishes it, and the home drawer renders the formatting as HTML rather
 * than as literal tags; a reader without announcement:manage has no entry in the
 * nav and is bounced off the route.
 *
 * The API half is scripts/verify-announcement.ps1. The browser half authors
 * everything itself; scripts/ui-announcement.ps1 only sweeps leftover UIANN rows.
 *
 * Usage:
 *   node announcement.mjs --prefix=UIANN-1234 --out=<dir> --edge=<path>
 *                         [--base=...] [--user=...] [--engineer=...] [--password=...]
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
const password = argv.password ?? 'Qms@2026'
const adminUser = argv.user ?? 'ying.zhou'
const engineerUser = argv.engineer ?? 'siyuan.li'
const prefix = argv.prefix ?? 'UIANN'

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
const wait = (ms) => new Promise((r) => setTimeout(r, ms))

async function newPage(user) {
  const context = browser.createBrowserContext
    ? await browser.createBrowserContext()
    : await browser.createIncognitoBrowserContext()
  const page = await context.newPage()
  await page.setViewport({ width: 1680, height: 1080 })
  await page.goto(`${base}/#/login`, { waitUntil: 'networkidle2', timeout: 40000 })
  await page.evaluate(() => localStorage.clear())
  await page.reload({ waitUntil: 'networkidle2' })
  await page.waitForSelector('input[type="text"]', { timeout: 20000 })
  await page.type('input[type="text"]', user)
  await page.type('input[type="password"]', password)
  await page.click('button[type="submit"]')
  await page.waitForFunction(() => !!document.querySelector('.app-sidebar .nav-item'), {
    timeout: 25000
  })
  await wait(1200)
  return { context, page }
}

async function shot(page, name) {
  await page.screenshot({ path: path.join(outDir, `ann-${name}.png`) })
}

/** Clicks the first visible element matching a selector, through the real mouse. */
async function mouseClick(page, selector) {
  const box = await page.evaluate((sel) => {
    const el = Array.from(document.querySelectorAll(sel)).find((e) => e.offsetParent !== null)
    if (!el) return null
    const r = el.getBoundingClientRect()
    return { x: r.left + r.width / 2, y: r.top + r.height / 2 }
  }, selector)
  if (!box) return false
  await page.mouse.click(box.x, box.y)
  return true
}

/** The management-table row whose text contains `needle`, flattened. */
async function rowText(page, needle) {
  return page.evaluate((t) => {
    const rows = Array.from(document.querySelectorAll('.el-table__body .el-table__row'))
    const row = rows.find((r) => r.innerText.includes(t))
    return row ? row.innerText.replace(/\s+/g, ' ').trim() : ''
  }, needle)
}

async function clickRowAction(page, needle, act) {
  const box = await page.evaluate(
    (t, a) => {
      const rows = Array.from(document.querySelectorAll('.el-table__body .el-table__row'))
      const row = rows.find((r) => r.innerText.includes(t))
      if (!row) return null
      const btn = Array.from(row.querySelectorAll(`[data-act="${a}"]`)).find(
        (b) => b.offsetParent !== null
      )
      if (!btn) return null
      const r = btn.getBoundingClientRect()
      return { x: r.left + r.width / 2, y: r.top + r.height / 2 }
    },
    needle,
    act
  )
  if (!box) return false
  await page.mouse.click(box.x, box.y)
  return true
}

async function confirmBox(page) {
  await page.waitForSelector('.el-message-box', { timeout: 15000 })
  await wait(500)
  await page.click('.el-message-box__btns .el-button--primary')
  await wait(2000)
}

let admin
let engineer

try {
  // =========================================================================
  // Administrator: author a formatted announcement and publish it
  // =========================================================================
  admin = await newPage(adminUser)
  const page = admin.page

  const navText = await page.evaluate(() => document.querySelector('.app-sidebar').innerText)
  note(
    'the administrator sees the announcement entry in the nav',
    navText.includes('公告管理'),
    navText.replace(/\s+/g, ' ').slice(0, 140)
  )

  await page.goto(`${base}/#/announcements/manage`, { waitUntil: 'networkidle2', timeout: 40000 })
  await page.waitForSelector('[data-ann-table]', { timeout: 25000 })
  await wait(1200)
  await shot(page, '1-list')

  const manageText = await page.evaluate(() => document.body.innerText)
  note('the page is titled 公告管理', manageText.includes('公告管理'), 'title missing')
  note(
    'the status filter offers 全部 / 草稿 / 已发布 / 已下架',
    ['全部', '草稿', '已发布', '已下架'].every((s) => manageText.includes(s)),
    'a status filter label is missing'
  )

  // --- create ---------------------------------------------------------------
  const title = `${prefix}-NOTICE`
  await mouseClick(page, '[data-ann-new]')
  await page.waitForSelector('.el-dialog', { timeout: 15000 })
  await page.waitForSelector('[data-rt-area] .ProseMirror', { timeout: 25000 })
  await wait(600)

  await page.click('[data-ann-field-title] input', { clickCount: 3 })
  await page.keyboard.press('Backspace')
  await page.type('[data-ann-field-title] input', title)
  await wait(300)

  // Bold run, then a two-item bullet list, all through the toolbar. A toolbar
  // command focuses the editor, but a button keeps DOM focus just long enough
  // that a following Enter would activate the button instead of the editor, so
  // the editor is focused explicitly before each keystroke that is not part of
  // the same click.
  await mouseClick(page, '[data-rt="bold"]')
  await page.click('[data-rt-area] .ProseMirror')
  await page.keyboard.type('Important notice')
  await mouseClick(page, '[data-rt="bold"]')
  await page.focus('[data-rt-area] .ProseMirror')
  await wait(150)
  await page.keyboard.press('Enter')
  await mouseClick(page, '[data-rt="bullet"]')
  await page.focus('[data-rt-area] .ProseMirror')
  await wait(150)
  await page.keyboard.type('first point')
  await page.keyboard.press('Enter')
  await page.keyboard.type('second point')
  await wait(400)
  await shot(page, '2-editor')

  await mouseClick(page, '[data-ann-save]')
  await page.waitForFunction((t) => document.body.innerText.includes(t), { timeout: 20000 }, title)
  await wait(1200)

  const draftRow = await rowText(page, title)
  note('saving adds the announcement to the list', draftRow.length > 0, draftRow)
  note('a new announcement starts as a draft', draftRow.includes('草稿'), draftRow)
  await shot(page, '3-draft')

  // --- publish --------------------------------------------------------------
  note('the draft offers a publish action', await clickRowAction(page, title, 'publish'), 'no publish button')
  await confirmBox(page)
  const publishedRow = await rowText(page, title)
  note('publishing flips the row to 已发布', publishedRow.includes('已发布'), publishedRow)

  // --- the home drawer renders the HTML ------------------------------------
  await page.goto(`${base}/#/`, { waitUntil: 'networkidle2', timeout: 40000 })
  await page.waitForSelector('.ann-item', { timeout: 25000 })
  await wait(1500)

  const opened = await page.evaluate((t) => {
    const item = Array.from(document.querySelectorAll('.ann-item')).find((el) =>
      el.innerText.includes(t)
    )
    if (!item) return false
    item.click()
    return true
  }, title)
  note('the published announcement appears on the home page', opened, 'not listed')
  await page.waitForSelector('.el-drawer .ann-body', { timeout: 15000 })
  await wait(1500)
  await shot(page, '4-home-drawer')

  const drawer = await page.evaluate(() => {
    const body = document.querySelector('.el-drawer .ann-body')
    if (!body) return null
    const strong = body.querySelector('strong')
    const weight = strong ? getComputedStyle(strong).fontWeight : ''
    return {
      text: body.innerText.replace(/\s+/g, ' ').trim(),
      strongCount: body.querySelectorAll('strong').length,
      liCount: body.querySelectorAll('ul li').length,
      weight
    }
  })
  note('the drawer is present', !!drawer, 'no drawer body')
  note('the bold run is rendered as HTML', !!drawer && drawer.strongCount >= 1, JSON.stringify(drawer))
  note('the bullet list is rendered as HTML', !!drawer && drawer.liCount >= 2, JSON.stringify(drawer))
  note(
    'the bold run is actually bold',
    !!drawer && (drawer.weight === 'bold' || parseInt(drawer.weight, 10) >= 600),
    drawer && drawer.weight
  )
  note(
    'the drawer does not show raw tags',
    !!drawer && !drawer.text.includes('<') && !drawer.text.includes('>'),
    drawer && drawer.text
  )

  // --- the layout holds at the two widths ----------------------------------
  await page.goto(`${base}/#/announcements/manage`, { waitUntil: 'networkidle2', timeout: 40000 })
  await page.waitForSelector('[data-ann-table]', { timeout: 25000 })
  for (const width of [1280, 1180]) {
    await page.setViewport({ width, height: 1000 })
    await wait(900)
    await shot(page, `5-width-${width}`)
    const geometry = await page.evaluate(() => {
      const card = document.querySelector('.card')?.getBoundingClientRect()
      const heading = document.querySelector('[data-ann-heading]')?.getBoundingClientRect()
      const filters = document.querySelector('[data-ann-filters]')?.getBoundingClientRect()
      return card && heading && filters
        ? {
            cardLeft: Math.round(card.left),
            headingRight: Math.round(heading.right),
            filtersLeft: Math.round(filters.left),
            filtersRight: Math.round(filters.right)
          }
        : null
    })
    note(
      `the status filter stays beside the list heading at ${width}px`,
      !!geometry && geometry.filtersLeft >= geometry.headingRight && geometry.cardLeft >= 0,
      JSON.stringify(geometry)
    )
  }

  await admin.context.close()

  // =========================================================================
  // Engineer: no entry, and bounced off the route
  // =========================================================================
  engineer = await newPage(engineerUser)
  const eng = engineer.page
  const engNav = await eng.evaluate(() => document.querySelector('.app-sidebar').innerText)
  note(
    'the engineer has no announcement entry in the nav',
    !engNav.includes('公告管理'),
    engNav.replace(/\s+/g, ' ').slice(0, 160)
  )

  await eng.goto(`${base}/#/announcements/manage`, { waitUntil: 'networkidle2', timeout: 40000 })
  await wait(2000)
  const engState = await eng.evaluate(() => ({
    table: !!document.querySelector('[data-ann-table]'),
    home: !!document.querySelector('.home-grid')
  }))
  note(
    'the engineer is redirected off the management route',
    !engState.table && engState.home && !eng.url().includes('announcements/manage'),
    `url=${eng.url()} state=${JSON.stringify(engState)}`
  )
  await shot(eng, '6-engineer')

  await engineer.context.close()
} catch (err) {
  note('announcement page run', false, err.message)
  const p = admin?.page ?? engineer?.page
  if (p) {
    try {
      await shot(p, 'error')
    } catch {
      /* ignore */
    }
  }
} finally {
  await admin?.context.close().catch(() => {})
  await engineer?.context.close().catch(() => {})
  await browser.close()
}

fs.writeFileSync(
  path.join(outDir, 'announcement_report.json'),
  JSON.stringify({ prefix, steps }, null, 2)
)
const failed = steps.filter((s) => !s.ok).length
console.log('')
console.log(`  RESULT : ${failed === 0 ? 'PASS' : 'FAIL (' + failed + ')'}`)
if (failed !== 0) process.exit(1)
