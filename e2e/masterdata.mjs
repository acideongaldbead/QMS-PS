/**
 * masterdata.mjs
 *
 * Drives the master data screens (PS-109 dictionary entries, PS-036 the
 * three-level failure type tree) in a real browser: maintaining a knowledge
 * category and seeing it appear in the knowledge centre's own sidebar, then
 * building, renaming, disabling and deleting a three-level branch.
 *
 * The sidebar check is the point of the dictionary half: it is the only
 * end-to-end proof that a master-data edit refreshes the shared dictionary cache
 * that every other screen reads from.
 *
 * The browser half authors its own data (dictionary `UIMD-`, failure type
 * W / Wa / Waa); scripts/ui-masterdata.ps1 sweeps those before and after.
 *
 * Every row lookup is scoped to one table: el-tabs keeps all panes in the DOM,
 * so an unscoped search finds rows of a tab that is not on screen.
 *
 * Usage:
 *   node masterdata.mjs --prefix=UIMD-1234 --out=<dir> --edge=<path> [--base=...]
 *                       [--user=...] [--engineer=...] [--password=...]
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
const prefix = argv.prefix ?? 'UIMD'

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

async function signIn(user) {
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
  await page.screenshot({ path: path.join(outDir, `md-${name}.png`) })
}

/**
 * Clicks the first visible element matching a selector, through the real mouse.
 *
 * Scrolls it into view first: mouse.click works in viewport coordinates, and a
 * row far down a fully expanded tree would otherwise be clicked below the fold,
 * where the click lands on nothing at all.
 */
async function mouseClick(page, selector) {
  const scrolled = await page.evaluate((sel) => {
    const el = Array.from(document.querySelectorAll(sel)).find((e) => e.offsetParent !== null)
    if (!el) return false
    el.scrollIntoView({ block: 'center', behavior: 'instant' })
    return true
  }, selector)
  if (!scrolled) return false
  await wait(250)
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

async function clickTab(page, labels) {
  // Scroll first: after working further down the page the tab strip is above the
  // viewport, and a click at a negative y lands on nothing -- which silently left
  // the previous tab on screen.
  const found = await page.evaluate((labels) => {
    const item = Array.from(document.querySelectorAll('.el-tabs__item')).find((e) =>
      labels.some((l) => e.innerText.trim() === l)
    )
    if (!item) return false
    item.scrollIntoView({ block: 'center', behavior: 'instant' })
    return true
  }, labels)
  if (!found) return false
  await wait(250)
  const box = await page.evaluate((labels) => {
    const item = Array.from(document.querySelectorAll('.el-tabs__item')).find((e) =>
      labels.some((l) => e.innerText.trim() === l)
    )
    if (!item) return null
    const r = item.getBoundingClientRect()
    return { x: r.left + r.width / 2, y: r.top + r.height / 2 }
  }, labels)
  if (!box) return false
  await page.mouse.click(box.x, box.y)
  await wait(700)
  return true
}

/** Confirms an Element Plus message box. */
async function confirmOk(page) {
  await wait(500)
  return mouseClick(page, '.el-message-box__btns .el-button--primary')
}

async function openAdmin(page) {
  await page.goto(`${base}/#/admin`, { waitUntil: 'networkidle2', timeout: 40000 })
  await page.waitForSelector('[data-admin-tabs]', { timeout: 25000 })
  await wait(800)
}

async function typeInto(page, selector, value) {
  await page.click(selector)
  await page.keyboard.down('Control')
  await page.keyboard.press('KeyA')
  await page.keyboard.up('Control')
  await page.keyboard.press('Delete')
  if (value) await page.type(selector, value)
}

/** The row action inside the dictionary row whose code cell carries the hook. */
function mdRowAction(page, code, act) {
  return clickInRow(page, '[data-md-row]', code, act)
}

function ftRowAction(page, code, act) {
  return clickInRow(page, '[data-ft-row]', code, act)
}

async function clickInRow(page, hook, code, act) {
  const scrolled = await page.evaluate(
    (hook, code, act) => {
      const cell = Array.from(document.querySelectorAll(hook)).find(
        (c) => c.getAttribute(hook.slice(1, -1)) === code
      )
      const row = cell?.closest('.el-table__row')
      if (!row) return false
      const btn = Array.from(row.querySelectorAll(`[data-act="${act}"]`)).find(
        (b) => b.offsetParent !== null
      )
      if (!btn) return false
      btn.scrollIntoView({ block: 'center', behavior: 'instant' })
      return true
    },
    hook,
    code,
    act
  )
  if (!scrolled) return false
  await wait(250)
  const box = await page.evaluate(
    (hook, code, act) => {
      const cell = Array.from(document.querySelectorAll(hook)).find(
        (c) => c.getAttribute(hook.slice(1, -1)) === code
      )
      const row = cell?.closest('.el-table__row')
      if (!row) return null
      const btn = Array.from(row.querySelectorAll(`[data-act="${act}"]`)).find(
        (b) => b.offsetParent !== null
      )
      if (!btn) return null
      const r = btn.getBoundingClientRect()
      return { x: r.left + r.width / 2, y: r.top + r.height / 2 }
    },
    hook,
    code,
    act
  )
  if (!box) return false
  await page.mouse.click(box.x, box.y)
  await wait(500)
  return true
}

const mdCodes = (page) =>
  page.evaluate(() =>
    Array.from(document.querySelectorAll('[data-md-row]')).map((e) => e.textContent.trim())
  )

/**
 * Polls until a condition holds.
 *
 * A fixed sleep after a write is not enough: the table re-fetches, and on a cold
 * server the reply can outlast any wait short enough to keep the run quick --
 * which showed up as the previous type's rows still being on screen and as an
 * assertion running before a freshly created node had arrived.
 */
async function waitFor(check, timeout = 20000) {
  const deadline = Date.now() + timeout
  while (Date.now() < deadline) {
    if (await check()) return true
    await wait(200)
  }
  return false
}

const waitForCode = (page, code) => waitFor(async () => (await mdCodes(page)).includes(code))

const waitForFtCode = (page, code) => waitFor(async () => (await ftCodes(page)).includes(code))

/** Reads the dictionary row's text, for assertions about its badges. */
async function mdRowText(page, code) {
  return page.evaluate((code) => {
    const cell = Array.from(document.querySelectorAll('[data-md-row]')).find(
      (c) => c.textContent.trim() === code
    )
    return cell?.closest('.el-table__row')?.innerText.replace(/\s+/g, ' ').trim() ?? ''
  }, code)
}

const ftCodes = (page) =>
  page.evaluate(() =>
    Array.from(document.querySelectorAll('[data-ft-row]')).map((e) => e.textContent.trim())
  )

async function ftRowText(page, code) {
  return page.evaluate((code) => {
    const cell = Array.from(document.querySelectorAll('[data-ft-row]')).find(
      (c) => c.textContent.trim() === code
    )
    const row = cell?.closest('.el-table__row')
    return row ? row.innerText.replace(/\s+/g, ' ').trim() : ''
  }, code)
}

async function countIn(page, selector) {
  return page.evaluate((sel) => {
    const el = document.querySelector(sel)
    const hit = el?.innerText.match(/(\d+)/)
    return hit ? Number(hit[1]) : -1
  }, selector)
}

async function hasMessageOfType(page, type) {
  return page.evaluate(
    (type) => !!document.querySelector(`.el-message--${type}`),
    type
  )
}

// ===========================================================================
const categoryCode = prefix + '-CAT'
const l1 = 'W'
const l2 = 'Wa'
const l3 = 'Waa'

const admin = await signIn(adminUser)
const page = admin.page

let opened = true
try {
  await openAdmin(page)
} catch (e) {
  opened = false
}
note('the administrator can open the administration screen', opened)

if (opened) {
  const tabCount = await page.evaluate(() => document.querySelectorAll('.el-tabs__item').length)
  note('the screen now offers five tabs', tabCount === 5, `tabs=${tabCount}`)

  // --- dictionary --------------------------------------------------------
  await clickTab(page, ['主数据管理', 'Master data'])
  const typeCount = await page.evaluate(
    () => document.querySelectorAll('[data-md-type]').length
  )
  note('the dictionary type list loads', typeCount >= 11, `types=${typeCount}`)

  // The priority list has no editable entries: its target days are config.
  await mouseClick(page, '[data-md-type="priority"]')
  await wait(600)
  note(
    'the priority list is shown as read-only',
    await page.evaluate(() => !!document.querySelector('[data-md-readonly]'))
  )
  note(
    'the read-only list offers no new-entry button',
    !(await page.evaluate(() => !!document.querySelector('[data-md-new]')))
  )

  await mouseClick(page, '[data-md-type="knowledge_category"]')
  await waitForCode(page, 'KNOWLEDGE_CATEGORY_001')
  const before = await mdCodes(page)
  note('the knowledge category list loads', before.length === 4, `rows=${before.length}`)
  await shot(page, '1-dictionary')

  await mouseClick(page, '[data-md-new]')
  await page.waitForSelector('[data-md-field-code] input', { timeout: 15000 })
  await typeInto(page, '[data-md-field-code] input', categoryCode)
  await typeInto(page, '[data-md-field-name] input', 'UIMD category')
  await mouseClick(page, '[data-md-save]')
  const created = await waitForCode(page, categoryCode)
  note('a dictionary entry is created in the UI', created, (await mdCodes(page)).join(','))
  await shot(page, '2-dictionary-created')

  // The knowledge centre's own sidebar reads the shared dictionary cache: if it
  // shows the new category, the cache was refreshed for every screen.
  await page.goto(`${base}/#/kb`, { waitUntil: 'networkidle2', timeout: 40000 })
  await page.waitForSelector('[data-cat]', { timeout: 25000 })
  await wait(900)
  const sidebarHasNew = await page.evaluate(
    (code) => !!document.querySelector(`[data-cat="${code}"]`),
    categoryCode
  )
  note('the new entry reaches the pickers without a reload', sidebarHasNew)
  await shot(page, '3-other-page')

  await openAdmin(page)
  await clickTab(page, ['主数据管理', 'Master data'])
  await mouseClick(page, '[data-md-type="knowledge_category"]')
  await waitForCode(page, categoryCode)

  await mdRowAction(page, categoryCode, 'md-disable')
  await confirmOk(page)
  await waitFor(async () => (await mdRowText(page, categoryCode)).includes('停用'))
  const disabledRow = await mdRowText(page, categoryCode)
  note('a dictionary entry can be disabled', disabledRow.includes('停用'), disabledRow)

  await page.goto(`${base}/#/kb`, { waitUntil: 'networkidle2', timeout: 40000 })
  await page.waitForSelector('[data-cat]', { timeout: 25000 })
  await wait(900)
  const sidebarAfterDisable = await page.evaluate(
    (code) => !!document.querySelector(`[data-cat="${code}"]`),
    categoryCode
  )
  note('a disabled entry leaves the pickers', !sidebarAfterDisable)

  await openAdmin(page)
  await clickTab(page, ['主数据管理', 'Master data'])
  await mouseClick(page, '[data-md-type="knowledge_category"]')
  await waitForCode(page, categoryCode)
  await mdRowAction(page, categoryCode, 'md-delete')
  await confirmOk(page)
  const removedFromList = await waitFor(async () => !(await mdCodes(page)).includes(categoryCode))
  note('a dictionary entry can be deleted', removedFromList)

  // --- failure type tree -------------------------------------------------
  await clickTab(page, ['失效类型', 'Failure types'])
  await wait(900)
  note('the failure type tree opens', (await ftCodes(page)).length === 34, `rows=${(await ftCodes(page)).length}`)
  note('the tree reports its size', (await countIn(page, '[data-ft-count]')) === 34, 'count text')
  await shot(page, '4-failure-types')

  await mouseClick(page, '[data-ft-new-root]')
  await page.waitForSelector('[data-ft-field-code] input', { timeout: 15000 })
  await typeInto(page, '[data-ft-field-code] input', l1)
  await typeInto(page, '[data-ft-field-name] input', 'W - Verify related')
  await mouseClick(page, '[data-ft-save]')
  note('a level-1 failure type is created', await waitForFtCode(page, l1))

  const rowActs = await page.evaluate((code) => {
    const cell = Array.from(document.querySelectorAll('[data-ft-row]')).find(
      (c) => c.textContent.trim() === code
    )
    const row = cell?.closest('.el-table__row')
    return {
      cell: !!cell,
      row: !!row,
      acts: row
        ? Array.from(row.querySelectorAll('[data-act]')).map(
            (b) => b.getAttribute('data-act') + ':' + (b.offsetParent !== null)
          )
        : []
    }
  }, l1)
  note(
    'a level-1 node offers the add-child control',
    rowActs.acts.some((a) => a === 'ft-add-child:true'),
    JSON.stringify(rowActs)
  )

  await ftRowAction(page, l1, 'ft-add-child')
  await page.waitForSelector('[data-ft-field-code] input', { timeout: 15000 })
  const suggested = await page.evaluate(
    () => document.querySelector('[data-ft-field-code] input')?.value ?? ''
  )
  note('the child code is suggested from its parent', suggested === l2, `suggested=${suggested}`)
  await typeInto(page, '[data-ft-field-code] input', l2)
  await typeInto(page, '[data-ft-field-name] input', 'Wa - Verify child')
  await mouseClick(page, '[data-ft-save]')
  note('a level-2 failure type is created', await waitForFtCode(page, l2))

  await ftRowAction(page, l2, 'ft-add-child')
  await page.waitForSelector('[data-ft-field-code] input', { timeout: 15000 })
  await typeInto(page, '[data-ft-field-code] input', l3)
  await typeInto(page, '[data-ft-field-name] input', 'Waa - Verify leaf')
  await mouseClick(page, '[data-ft-save]')
  note('a level-3 failure type is created', await waitForFtCode(page, l3))
  note(
    'the tree is three nodes bigger',
    await waitFor(async () => (await countIn(page, '[data-ft-count]')) === 37),
    'count text'
  )

  await ftRowAction(page, l3, 'ft-rename')
  await page.waitForSelector('[data-ft-field-name] input', { timeout: 15000 })
  await typeInto(page, '[data-ft-field-name] input', 'Waa - Renamed leaf')
  await mouseClick(page, '[data-ft-save]')
  const renamed = await waitFor(async () =>
    (await ftRowText(page, l3)).includes('Waa - Renamed leaf')
  )
  note('a failure type can be renamed', renamed, await ftRowText(page, l3))
  await shot(page, '5-tree-built')

  await ftRowAction(page, l2, 'ft-disable')
  await confirmOk(page)
  await waitFor(async () => (await ftRowText(page, l2)).includes('停用'))
  await waitFor(async () => (await ftRowText(page, l3)).includes('停用'))
  note('a branch can be disabled', (await ftRowText(page, l2)).includes('停用'), await ftRowText(page, l2))
  note(
    'disabling a branch disables its child too',
    (await ftRowText(page, l3)).includes('停用'),
    await ftRowText(page, l3)
  )

  await ftRowAction(page, l2, 'ft-delete')
  await confirmOk(page)
  const refused = await waitFor(() => hasMessageOfType(page, 'error'))
  note('a node with children cannot be deleted', (await ftCodes(page)).includes(l2))
  note('the refusal is explained on screen', refused)
  await wait(3200)

  for (const code of [l3, l2, l1]) {
    await ftRowAction(page, code, 'ft-delete')
    await confirmOk(page)
    await waitFor(async () => !(await ftCodes(page)).includes(code))
  }
  note('the branch can be deleted leaf first', !(await ftCodes(page)).some((c) => c.startsWith(l1)))
  note(
    'the tree is back to 34 nodes',
    await waitFor(async () => (await countIn(page, '[data-ft-count]')) === 34),
    'count text'
  )

  // --- layout at both widths ---------------------------------------------
  await clickTab(page, ['主数据管理', 'Master data'])
  const activePane = await page.evaluate(() => {
    const table = document.querySelector('[data-md-table]')
    return !!table && table.getBoundingClientRect().width > 0
  })
  note('the dictionary tab is on screen for the layout check', activePane)

  const tabs = await page.evaluate(() => {
    const tops = Array.from(document.querySelectorAll('.el-tabs__item')).map((t) =>
      Math.round(t.getBoundingClientRect().top)
    )
    return { count: tops.length, sameRow: Math.max(...tops) - Math.min(...tops) <= 2 }
  })
  note('the five tabs stay on one row', tabs.count === 5 && tabs.sameRow, JSON.stringify(tabs))

  for (const width of [1280, 1180]) {
    await page.setViewport({ width, height: 1000 })
    await wait(900)
    await shot(page, `6-width-${width}`)
    const geometry = await page.evaluate(() => {
      const root = document.querySelector('[data-md-table]')
      const list = document.querySelector('[data-md-types]')?.getBoundingClientRect()
      const table = root?.getBoundingClientRect()
      if (!root || !list || !table) return null
      const wrap = root.querySelector('.el-scrollbar__wrap')
      const heads = Array.from(root.querySelectorAll('.el-table__header th'))
      const lastHead = heads[heads.length - 1]?.getBoundingClientRect()
      return {
        listRight: Math.round(list.right),
        listWidth: Math.round(list.width),
        tableLeft: Math.round(table.left),
        tableWidth: Math.round(table.width),
        tableRight: Math.round(table.right),
        wrapClient: wrap ? wrap.clientWidth : 0,
        wrapScroll: wrap ? wrap.scrollWidth : 0,
        lastColumnRight: lastHead ? Math.round(lastHead.right) : 0
      }
    })
    // Non-zero widths matter: a hidden pane reports 0x0 at the origin, which
    // would satisfy a bare "list is left of table" comparison.
    note(
      `the type list stays beside the entries at ${width}px`,
      !!geometry &&
        geometry.listWidth > 0 &&
        geometry.tableWidth > 0 &&
        geometry.listRight <= geometry.tableLeft + 2,
      JSON.stringify(geometry)
    )
    // Every column has to stay reachable: either it fits, or the table scrolls
    // sideways instead of silently clipping the actions away.
    const fits = !!geometry && geometry.lastColumnRight <= geometry.tableRight + 1
    const scrolls = !!geometry && geometry.wrapScroll > geometry.wrapClient
    note(
      `every entry column is reachable at ${width}px`,
      fits || scrolls,
      JSON.stringify(geometry)
    )
  }

  // --- an engineer never gets in -----------------------------------------
  const engineer = await signIn(engineerUser)
  const engPage = engineer.page
  const nav = await engPage.evaluate(() =>
    Array.from(document.querySelectorAll('.app-sidebar .nav-item')).map((n) => n.innerText.trim())
  )
  note(
    'the engineer has no administration entry',
    !nav.some((n) => n.includes('系统管理')),
    nav.join(' | ')
  )
  await engPage.goto(`${base}/#/admin`, { waitUntil: 'networkidle2', timeout: 40000 })
  await wait(1500)
  const engHash = await engPage.evaluate(() => location.hash)
  note('the engineer is bounced off the route', engHash !== '#/admin', engHash)
}

const failed = steps.filter((s) => !s.ok).length
fs.writeFileSync(
  path.join(outDir, 'masterdata_report.json'),
  JSON.stringify({ prefix, categoryCode, passed: steps.length - failed, failed, steps }, null, 2)
)
console.log('')
console.log(`  RESULT : ${failed === 0 ? 'PASS' : 'FAIL (' + failed + ')'}`)
for (const s of steps) {
  if (!s.ok) console.log(`    FAILED: ${s.name}  ${s.detail ?? ''}`)
}
await browser.close()
process.exit(failed === 0 ? 0 : 1)
