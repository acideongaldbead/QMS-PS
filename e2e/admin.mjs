/**
 * admin.mjs
 *
 * Drives the system-administration screen (requirement 3.12) in a real browser:
 * the three tabs, the read-only preset roles, building a custom role, ticking a
 * permission on the matrix, assigning the role to somebody, resetting a password,
 * and the fact that a user without the permission never gets in.
 *
 * Every row lookup is scoped to one table on purpose: el-tabs keeps all panes in
 * the DOM, so an unscoped search finds the users table's rows while the roles tab
 * is on screen -- "管理员" matches a role badge on a user row too.
 *
 * The API half is scripts/verify-admin.ps1. The browser half authors its own role
 * (prefix UIADM-); scripts/ui-admin.ps1 sweeps those and restores the account it
 * resets.
 *
 * Usage:
 *   node admin.mjs --prefix=UIADM-1234 --out=<dir> --edge=<path> [--base=...]
 *                  [--user=...] [--engineer=...] [--spare=...] [--password=...]
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
const spareUser = argv.spare ?? ''
const prefix = argv.prefix ?? 'UIADM'

const USERS = '[data-admin-users]'
const ROLES = '[data-admin-roles]'
const MATRIX = '[data-admin-matrix]'

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

async function signInWith(user, pwd) {
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
  await page.type('input[type="password"]', pwd)
  await page.click('button[type="submit"]')
  await page.waitForFunction(() => !!document.querySelector('.app-sidebar .nav-item'), {
    timeout: 25000
  })
  await wait(1200)
  return { context, page }
}

const signIn = (user) => signInWith(user, password)

async function shot(page, name) {
  await page.screenshot({ path: path.join(outDir, `admin-${name}.png`) })
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

/** Tab labels differ per language, so accept any of the candidates. */
async function clickTab(page, labels) {
  const box = await page.evaluate((labels) => {
    const items = Array.from(document.querySelectorAll('.el-tabs__item'))
    const item = items.find((e) => labels.some((l) => e.innerText.trim() === l))
    if (!item) return null
    const r = item.getBoundingClientRect()
    return { x: r.left + r.width / 2, y: r.top + r.height / 2 }
  }, labels)
  if (!box) return false
  await page.mouse.click(box.x, box.y)
  await wait(700)
  return true
}

async function openAdmin(page) {
  await page.goto(`${base}/#/admin`, { waitUntil: 'networkidle2', timeout: 40000 })
  await page.waitForSelector(USERS, { timeout: 25000 })
  await wait(800)
}

const rowCount = (page, scope) =>
  page.evaluate((s) => document.querySelectorAll(`${s} .el-table__body .el-table__row`).length, scope)

async function rowText(page, scope, needle) {
  return page.evaluate(
    (s, t) => {
      const rows = Array.from(document.querySelectorAll(`${s} .el-table__body .el-table__row`))
      const row = rows.find((r) => r.innerText.includes(t))
      return row ? row.innerText.replace(/\s+/g, ' ').trim() : ''
    },
    scope,
    needle
  )
}

async function hasAct(page, scope, needle, act) {
  return page.evaluate(
    (s, t, a) => {
      const rows = Array.from(document.querySelectorAll(`${s} .el-table__body .el-table__row`))
      const row = rows.find((r) => r.innerText.includes(t))
      if (!row) return false
      return Array.from(row.querySelectorAll(`[data-act="${a}"]`)).some(
        (b) => b.offsetParent !== null
      )
    },
    scope,
    needle,
    act
  )
}

async function clickRowAction(page, scope, needle, act) {
  const box = await page.evaluate(
    (s, t, a) => {
      const rows = Array.from(document.querySelectorAll(`${s} .el-table__body .el-table__row`))
      const row = rows.find((r) => r.innerText.includes(t))
      if (!row) return null
      const btn = Array.from(row.querySelectorAll(`[data-act="${a}"]`)).find(
        (b) => b.offsetParent !== null
      )
      if (!btn) return null
      const r = btn.getBoundingClientRect()
      return { x: r.left + r.width / 2, y: r.top + r.height / 2 }
    },
    scope,
    needle,
    act
  )
  if (!box) return false
  await page.mouse.click(box.x, box.y)
  await wait(500)
  return true
}

/** Reads the text of `[attr]` inside the row whose text contains `needle`. */
async function rowField(page, scope, needle, attr) {
  return page.evaluate(
    (s, t, a) => {
      const rows = Array.from(document.querySelectorAll(`${s} .el-table__body .el-table__row`))
      const row = rows.find((r) => r.innerText.includes(t))
      if (!row) return null
      const el = row.querySelector(`[${a}]`)
      return el ? el.innerText.trim() : null
    },
    scope,
    needle,
    attr
  )
}

/** The matrix cell for a role column and a permission row, addressed by handle. */
async function cellHandle(page, roleName, permissionCode) {
  return page.evaluate(
    (scope, roleName, code) => {
      const root = document.querySelector(scope)
      if (!root) return null
      const head = Array.from(root.querySelectorAll('[data-role-col]')).find(
        (h) => h.innerText.trim() === roleName
      )
      if (!head) return null
      const roleId = head.getAttribute('data-role-col')
      const rows = Array.from(root.querySelectorAll('.el-table__body .el-table__row'))
      const row = rows.find((r) => r.innerText.includes(code))
      if (!row) return null
      const cell = Array.from(row.querySelectorAll('[data-perm-cell]')).find((c) =>
        c.getAttribute('data-perm-cell').startsWith(roleId + ':')
      )
      return cell ? cell.getAttribute('data-perm-cell') : null
    },
    MATRIX,
    roleName,
    permissionCode
  )
}

const cellChecked = (page, handle) =>
  page.evaluate((h) => {
    const cell = document.querySelector(`[data-perm-cell="${h}"]`)
    if (!cell) return false
    const input = cell.querySelector('input[type="checkbox"]')
    if (input) return input.checked
    const box = cell.querySelector('.el-checkbox')
    return !!box && box.classList.contains('is-checked')
  }, handle)

const tickCell = (page, handle) => mouseClick(page, `[data-perm-cell="${handle}"] .el-checkbox`)

/** Picks an option out of an open Element Plus select. */
async function pickOption(page, text) {
  const box = await page.evaluate((needle) => {
    const items = Array.from(document.querySelectorAll('.el-select-dropdown__item')).filter(
      (e) => e.offsetParent !== null
    )
    const item = items.find((e) => e.innerText.includes(needle))
    if (!item) return null
    const r = item.getBoundingClientRect()
    return { x: r.left + r.width / 2, y: r.top + r.height / 2 }
  }, text)
  if (!box) return false
  await page.mouse.click(box.x, box.y)
  await wait(400)
  return true
}

async function typeInto(page, selector, value) {
  await page.click(selector)
  await page.keyboard.down('Control')
  await page.keyboard.press('KeyA')
  await page.keyboard.up('Control')
  await page.keyboard.press('Delete')
  await page.type(selector, value)
}

const layoutCheck = (page) =>
  page.evaluate((scope) => {
    const tabs = Array.from(document.querySelectorAll('.el-tabs__item'))
    const tops = tabs.map((t) => Math.round(t.getBoundingClientRect().top))
    const table = document.querySelector(scope)
    const rect = table?.getBoundingClientRect()
    return {
      tabs: tabs.length,
      sameRow: Math.max(...tops) - Math.min(...tops) <= 2,
      tableWidth: rect ? Math.round(rect.width) : 0,
      viewport: window.innerWidth
    }
  }, USERS)

// ===========================================================================
const roleName = `${prefix}-ROLE`
const tempPassword = 'Uiadm@2026'

const admin = await signIn(adminUser)
const page = admin.page

// --- the screen opens on the users tab -------------------------------------
let opened = true
try {
  await openAdmin(page)
} catch (e) {
  opened = false
}
note('the administrator can open the administration screen', opened)
if (opened) {
  const usersShown = await page.evaluate((s) => !!document.querySelector(s), USERS)
  note('the users tab is shown first', usersShown)

  const userRows = await rowCount(page, USERS)
  note('the user list is populated', userRows >= 9, `rows=${userRows}`)
  await shot(page, '1-users')

  const adminRow = await rowText(page, USERS, adminUser)
  note('the administrator row carries the administrator role', adminRow.includes('管理员'), adminRow)
  const engineerRow = await rowText(page, USERS, engineerUser)
  note(
    'the engineer row carries a quality-engineer role',
    engineerRow.includes('质量工程师'),
    engineerRow
  )
  note(
    'the account column shows a state badge',
    (await rowField(page, USERS, adminUser, 'data-admin-account-state')) !== null
  )

  // --- roles tab: preset roles are read-only ---------------------------------
  await clickTab(page, ['角色管理', 'Roles'])
  const roleRows = await rowCount(page, ROLES)
  note('the roles tab opens', roleRows >= 4, `rows=${roleRows}`)
  note('the four preset roles are listed', roleRows >= 4, `rows=${roleRows}`)

  const adminType = await rowField(page, ROLES, '管理员', 'data-admin-role-type')
  note('a preset role is marked as preset', adminType === '预设', String(adminType))
  note('a preset role offers no rename control', !(await hasAct(page, ROLES, '管理员', 'rename')))
  note('a preset role offers no delete control', !(await hasAct(page, ROLES, '管理员', 'delete-role')))
  note('a preset role offers no disable control', !(await hasAct(page, ROLES, '管理员', 'disable-role')))
  note('a preset role can still be copied', await hasAct(page, ROLES, '管理员', 'copy'))

  // --- build a custom role ---------------------------------------------------
  await mouseClick(page, '[data-admin-role-new]')
  await page.waitForSelector('[data-admin-role-field-name] input', { timeout: 15000 })
  await page.type('[data-admin-role-field-name] input', roleName)
  await mouseClick(page, '[data-admin-role-save]')
  await wait(1400)

  const newRoleText = await rowText(page, ROLES, roleName)
  note('a custom role can be created', newRoleText.includes(roleName), newRoleText)
  const newRoleType = await rowField(page, ROLES, roleName, 'data-admin-role-type')
  note('the new role is marked custom', newRoleType === '自定义', String(newRoleType))
  const newRolePerms = await rowField(page, ROLES, roleName, 'data-admin-role-perms')
  note('the new role starts with no permissions', newRolePerms === '0', String(newRolePerms))
  await shot(page, '2-roles')

  // --- the matrix ------------------------------------------------------------
  await clickTab(page, ['权限矩阵', 'Permission matrix'])
  note(
    'the matrix opens',
    await page.evaluate((s) => !!document.querySelector(s), MATRIX)
  )
  const headerHasRole = await page.evaluate(
    (s, name) =>
      Array.from(document.querySelectorAll(`${s} [data-role-col]`)).some(
        (h) => h.innerText.trim() === name
      ),
    MATRIX,
    roleName
  )
  note('the new role has a column in the matrix', headerHasRole)

  const cell = await cellHandle(page, roleName, 'complaint:view')
  note('the matrix addresses a cell by role and permission', !!cell, String(cell))
  const before = cell ? await cellChecked(page, cell) : true
  if (cell) await tickCell(page, cell)
  await wait(1600)
  const afterTick = cell ? await cellChecked(page, cell) : false
  note(
    'ticking a cell on a custom role stores the permission',
    !!cell && afterTick && !before,
    `cell=${cell} before=${before} after=${afterTick}`
  )
  await shot(page, '3-matrix')

  const presetCell = await cellHandle(page, '管理员', 'complaint:view')
  const presetDisabled = presetCell
    ? await page.evaluate(
        (h) => !!document.querySelector(`[data-perm-cell="${h}"] .el-checkbox.is-disabled`),
        presetCell
      )
    : false
  note("a preset role's matrix cell is read-only", presetDisabled)

  await clickTab(page, ['角色管理', 'Roles'])
  const permCount = await rowField(page, ROLES, roleName, 'data-admin-role-perms')
  note('the role now reports one permission', permCount === '1', String(permCount))

  // --- assign the new role to the engineer -----------------------------------
  await clickTab(page, ['用户管理', 'Users'])
  await clickRowAction(page, USERS, engineerUser, 'assign')
  await page.waitForSelector('[data-admin-assign-field]', { timeout: 15000 })
  await mouseClick(page, '[data-admin-assign-field] .el-select')
  await wait(700)
  const pickedOption = await pickOption(page, roleName)
  note('the new role is offered in the assign dialog', pickedOption)
  // Clicking inside the dialog closes the dropdown without closing the dialog;
  // Escape would close both.
  await mouseClick(page, '.el-dialog__header')
  await wait(400)
  await mouseClick(page, '[data-admin-assign-save]')
  await wait(1600)

  const engineerAfter = await rowText(page, USERS, engineerUser)
  note('the engineer row now shows the new role', engineerAfter.includes(roleName), engineerAfter)
  await shot(page, '4-assigned')

  // --- reset a password ------------------------------------------------------
  if (spareUser) {
    await clickRowAction(page, USERS, spareUser, 'reset')
    await page.waitForSelector('[data-admin-reset-field] input', { timeout: 15000 })
    await typeInto(page, '[data-admin-reset-field] input', 'short')
    await mouseClick(page, '[data-admin-reset-save]')
    await wait(1000)
    const warned = await page.evaluate(
      () => !!document.querySelector('.el-message--warning, .el-message--error')
    )
    note('the reset dialog refuses a too-short password', warned)

    await wait(3400)
    await typeInto(page, '[data-admin-reset-field] input', tempPassword)
    await mouseClick(page, '[data-admin-reset-save]')
    await wait(1800)
    const spareState = await rowField(page, USERS, spareUser, 'data-admin-account-state')
    note(
      'a reset marks the account as password-due',
      (spareState ?? '').includes('待改密'),
      String(spareState)
    )
    await shot(page, '5-reset')

    // --- the forced change, from that account's side -------------------------
    const forced = await signInWith(spareUser, tempPassword)
    const fPage = forced.page
    const landed = await fPage.evaluate(() => location.hash)
    note('a reset account lands on the change screen', landed === '#/change-password', landed)
    const noticeShown = await fPage.evaluate(() => !!document.querySelector('[data-cp-forced]'))
    note('the forced change is explained on the screen', noticeShown)
    await shot(fPage, '8-forced-change')

    await fPage.goto(`${base}/#/kb`, { waitUntil: 'networkidle2', timeout: 40000 })
    await wait(1400)
    const bouncedHash = await fPage.evaluate(() => location.hash)
    note(
      'the forced session cannot reach another screen',
      bouncedHash === '#/change-password',
      bouncedHash
    )

    const newPassword = tempPassword + 'x'
    await typeInto(fPage, '[data-cp-old] input', tempPassword)
    await typeInto(fPage, '[data-cp-new] input', newPassword)
    await typeInto(fPage, '[data-cp-confirm] input', newPassword)
    await mouseClick(fPage, '[data-cp-save]')
    await wait(1800)
    const afterChange = await fPage.evaluate(() => location.hash)
    const stillForced = await fPage.evaluate(() => !!document.querySelector('[data-cp-forced]'))
    note('the password can be changed from the forced screen', afterChange !== '#/change-password', afterChange)
    note('the forced state is cleared after the change', !stillForced)
    await shot(fPage, '9-after-change')
  }

  // --- layout at both widths -------------------------------------------------
  await clickTab(page, ['用户管理', 'Users'])
  // A missing i18n key renders as its own path; catch that rather than shipping it.
  const untranslated = await page.evaluate(
    () => document.body.innerText.match(/\b(?:admin|changePwd)\.[a-zA-Z]+/g) ?? []
  )
  note(
    'no untranslated label is left on the screen',
    untranslated.length === 0,
    untranslated.join(',')
  )

  for (const width of [1280, 1180]) {
    await page.setViewport({ width, height: 1000 })
    await wait(900)
    await shot(page, `6-width-${width}`)
    const layout = await layoutCheck(page)
    note(
      `the tabs stay on one row at ${width}px`,
      layout.sameRow && layout.tabs >= 3,
      JSON.stringify(layout)
    )
    note(
      `the table fits the viewport at ${width}px`,
      layout.tableWidth > 0 && layout.tableWidth <= layout.viewport,
      JSON.stringify(layout)
    )
  }

  // --- a user without the permission never gets in ---------------------------
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
  note('the engineer is bounced off the administration route', engHash !== '#/admin', engHash)
  await shot(engPage, '7-engineer')
} else {
  note('further checks need the screen', false, 'the administration screen did not load')
}

const failed = steps.filter((s) => !s.ok).length
fs.writeFileSync(
  path.join(outDir, 'admin_report.json'),
  JSON.stringify({ prefix, roleName, passed: steps.length - failed, failed, steps }, null, 2)
)
console.log('')
console.log(`  RESULT : ${failed === 0 ? 'PASS' : 'FAIL (' + failed + ')'}`)
for (const s of steps) {
  if (!s.ok) console.log(`    FAILED: ${s.name}  ${s.detail ?? ''}`)
}
await browser.close()
process.exit(failed === 0 ? 0 : 1)
