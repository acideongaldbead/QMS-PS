<script setup lang="ts">
import { computed, onMounted, reactive, ref } from 'vue'
import { useI18n } from 'vue-i18n'
import { ElMessage, ElMessageBox } from 'element-plus'
import { errorMessage } from '@/api/http'
import { adminApi, type AdminPermission, type AdminRole, type AdminUser } from '@/api/admin'
import { useAuthStore } from '@/stores/auth'
import QmsIcon from '@/components/QmsIcon.vue'
import RowAction from '@/components/RowAction.vue'
import MasterDataPanel from '@/views/admin/MasterDataPanel.vue'
import FailureTypePanel from '@/views/admin/FailureTypePanel.vue'

/**
 * System administration (requirement 3.12): users, roles and the permission
 * matrix, in that order.
 *
 * The route is gated on admin.all; every write here additionally needs
 * rbac:manage, so a role holding only admin.all sees the data with no controls --
 * the same split the API enforces, kept visible rather than discovered as a 403.
 */
const { t, te, locale } = useI18n()
const auth = useAuthStore()

const canManage = computed(() => auth.can('rbac:manage'))
const isZh = computed(() => locale.value.startsWith('zh'))

const activeTab = ref('users')

const users = ref<AdminUser[]>([])
const roles = ref<AdminRole[]>([])
const permissions = ref<AdminPermission[]>([])
const loading = ref(false)
const userKeyword = ref('')

const PRESET = 'PRESET'
const CUSTOM = 'CUSTOM'
const MIN_PASSWORD = 8

const roleNameByCode = computed(() => {
  const map = new Map<string, string>()
  for (const role of roles.value) map.set(role.roleCode, role.roleName)
  return map
})

/** A disabled role cannot be assigned, so the dialog drops it instead of sending it. */
const activeRoleCodes = computed(
  () => new Set(roles.value.filter((r) => r.isActive).map((r) => r.roleCode))
)

const filteredUsers = computed(() => {
  const keyword = userKeyword.value.trim().toLowerCase()
  if (!keyword) return users.value
  return users.value.filter((u) =>
    [u.name, u.nameEn, u.employeeId, u.username, u.deptL1, u.deptL2].some((value) =>
      (value ?? '').toLowerCase().includes(keyword)
    )
  )
})

/** Permissions arrive grouped by module already, so the first column can borrow a rowspan. */
const moduleSpans = computed(() => {
  const spans: Record<number, number> = {}
  let i = 0
  while (i < permissions.value.length) {
    const module = permissions.value[i].moduleCode ?? ''
    let j = i
    while (
      j + 1 < permissions.value.length &&
      (permissions.value[j + 1].moduleCode ?? '') === module
    ) {
      j++
    }
    spans[i] = j - i + 1
    for (let k = i + 1; k <= j; k++) spans[k] = 0
    i = j + 1
  }
  return spans
})

function spanMethod({ rowIndex, columnIndex }: { rowIndex: number; columnIndex: number }) {
  if (columnIndex !== 0) return [1, 1]
  const span = moduleSpans.value[rowIndex] ?? 1
  return span === 0 ? [0, 0] : [span, 1]
}

/** Module and level codes have no lookup table, so the label map lives in i18n. */
function moduleLabel(code?: string | null): string {
  if (!code) return '—'
  return te(`admin.module.${code}`) ? t(`admin.module.${code}`) : code
}

function levelLabel(code?: string | null): string {
  if (!code) return '—'
  return te(`admin.level.${code}`) ? t(`admin.level.${code}`) : code
}

function permissionLabel(permission: AdminPermission): string {
  if (isZh.value) return permission.permissionName
  return permission.permissionNameEn || permission.permissionName
}

function roleLabel(code: string): string {
  return roleNameByCode.value.get(code) ?? code
}

function department(user: AdminUser): string {
  return [user.deptL1, user.deptL2].filter(Boolean).join(' / ') || '—'
}

/** Every account flag that warrants a badge; a healthy account shows exactly one. */
function accountBadges(user: AdminUser): { label: string; cls: string }[] {
  if (user.accountActive == null) {
    return [{ label: t('admin.noAccount'), cls: 'badge badge-neutral' }]
  }
  const badges: { label: string; cls: string }[] = []
  if (!user.accountActive) {
    badges.push({ label: t('admin.accountInactive'), cls: 'badge badge-danger' })
  }
  if (user.locked) {
    badges.push({ label: t('admin.accountLocked'), cls: 'badge badge-warning' })
  }
  if (user.mustChangePwd) {
    badges.push({ label: t('admin.mustChangePwdBadge'), cls: 'badge badge-warning' })
  }
  if (!badges.length) {
    badges.push({ label: t('admin.accountActive'), cls: 'badge badge-success' })
  }
  return badges
}

async function load() {
  loading.value = true
  try {
    const [userList, roleList, permissionList] = await Promise.all([
      adminApi.users(),
      adminApi.roles(),
      adminApi.permissions()
    ])
    users.value = userList
    roles.value = roleList
    permissions.value = permissionList
  } catch (e) {
    ElMessage.error(t('admin.loadFailed') + errorMessage(e))
  } finally {
    loading.value = false
  }
}

async function reloadUsers() {
  users.value = await adminApi.users()
}

async function reloadRoles() {
  roles.value = await adminApi.roles()
}

function confirmThen(message: string, title: string): Promise<boolean> {
  return ElMessageBox.confirm(message, title, {
    type: 'warning',
    confirmButtonText: t('common.confirm'),
    cancelButtonText: t('common.cancel')
  })
    .then(() => true)
    .catch(() => false)
}

// ------------------------------------------------------------------ users

const assignOpen = ref(false)
const assignTarget = ref<AdminUser | null>(null)
const assignSelection = ref<string[]>([])
const assignSaving = ref(false)

/** Selected roles that are disabled -- shown, but never sent. */
const assignDropped = computed(() =>
  assignSelection.value.filter((code) => !activeRoleCodes.value.has(code)).map(roleLabel)
)

function openAssign(user: AdminUser) {
  assignTarget.value = user
  assignSelection.value = [...user.roleCodes]
  assignOpen.value = true
}

async function saveAssign() {
  const target = assignTarget.value
  if (!target) return
  assignSaving.value = true
  try {
    const codes = assignSelection.value.filter((code) => activeRoleCodes.value.has(code))
    await adminApi.assignRoles(target.employeeId, codes)
    ElMessage.success(t('admin.assignSaved'))
    assignOpen.value = false
    await reloadUsers()
  } catch (e) {
    ElMessage.error(errorMessage(e))
  } finally {
    assignSaving.value = false
  }
}

const resetOpen = ref(false)
const resetTarget = ref<AdminUser | null>(null)
const resetPassword = ref('')
const resetSaving = ref(false)

function openReset(user: AdminUser) {
  resetTarget.value = user
  resetPassword.value = ''
  resetOpen.value = true
}

async function saveReset() {
  const target = resetTarget.value
  if (!target) return
  if (resetPassword.value.length < MIN_PASSWORD) {
    ElMessage.warning(t('admin.passwordRule'))
    return
  }
  resetSaving.value = true
  try {
    await adminApi.resetPassword(target.employeeId, resetPassword.value)
    ElMessage.success(t('admin.resetDone'))
    resetOpen.value = false
    await reloadUsers()
  } catch (e) {
    ElMessage.error(errorMessage(e))
  } finally {
    resetSaving.value = false
  }
}

async function toggleAccount(user: AdminUser) {
  const enabling = user.accountActive === false
  const ok = await confirmThen(
    t(enabling ? 'admin.activateConfirm' : 'admin.deactivateConfirm', { name: user.name }),
    t(enabling ? 'admin.activateAccount' : 'admin.deactivateAccount')
  )
  if (!ok) return
  try {
    if (enabling) {
      await adminApi.activateAccount(user.employeeId)
    } else {
      await adminApi.deactivateAccount(user.employeeId)
    }
    ElMessage.success(t(enabling ? 'admin.accountEnabled' : 'admin.accountDisabled'))
    await reloadUsers()
  } catch (e) {
    ElMessage.error(errorMessage(e))
  }
}

async function unlockAccount(user: AdminUser) {
  const ok = await confirmThen(t('admin.unlockConfirm', { name: user.name }), t('admin.unlock'))
  if (!ok) return
  try {
    await adminApi.unlock(user.employeeId)
    ElMessage.success(t('admin.unlockDone'))
    await reloadUsers()
  } catch (e) {
    ElMessage.error(errorMessage(e))
  }
}

// ------------------------------------------------------------------ roles

const roleOpen = ref(false)
const editingRoleId = ref<number | null>(null)
const roleForm = reactive({ roleName: '', roleNameEn: '' })
const roleSaving = ref(false)

function openNewRole() {
  editingRoleId.value = null
  roleForm.roleName = ''
  roleForm.roleNameEn = ''
  roleOpen.value = true
}

function openRename(role: AdminRole) {
  editingRoleId.value = role.roleId
  roleForm.roleName = role.roleName
  roleForm.roleNameEn = role.roleNameEn ?? ''
  roleOpen.value = true
}

async function saveRole() {
  if (!roleForm.roleName.trim()) {
    ElMessage.warning(t('admin.roleNameRequired'))
    return
  }
  roleSaving.value = true
  try {
    const body = {
      roleName: roleForm.roleName.trim(),
      roleNameEn: roleForm.roleNameEn.trim() || null
    }
    if (editingRoleId.value == null) {
      await adminApi.createRole(body)
    } else {
      await adminApi.renameRole(editingRoleId.value, body)
    }
    ElMessage.success(t('admin.roleSaved'))
    roleOpen.value = false
    await reloadRoles()
  } catch (e) {
    ElMessage.error(errorMessage(e))
  } finally {
    roleSaving.value = false
  }
}

async function copyRole(role: AdminRole) {
  const ok = await confirmThen(
    t('admin.copyRoleConfirm', { name: role.roleName }),
    t('admin.copyRole')
  )
  if (!ok) return
  try {
    await adminApi.copyRole(role.roleId)
    ElMessage.success(t('admin.roleCopied'))
    await reloadRoles()
  } catch (e) {
    ElMessage.error(errorMessage(e))
  }
}

async function toggleRole(role: AdminRole) {
  const enabling = !role.isActive
  const ok = await confirmThen(
    t(enabling ? 'admin.activateConfirm' : 'admin.deactivateConfirm', { name: role.roleName }),
    t(enabling ? 'admin.activateRole' : 'admin.deactivateRole')
  )
  if (!ok) return
  try {
    if (enabling) {
      await adminApi.activateRole(role.roleId)
    } else {
      await adminApi.deactivateRole(role.roleId)
    }
    ElMessage.success(t(enabling ? 'admin.roleActivated' : 'admin.roleDeactivated'))
    await reloadRoles()
  } catch (e) {
    ElMessage.error(errorMessage(e))
  }
}

async function removeRole(role: AdminRole) {
  const ok = await confirmThen(
    t('admin.deleteRoleConfirm', { name: role.roleName }),
    t('admin.deleteRole')
  )
  if (!ok) return
  try {
    await adminApi.deleteRole(role.roleId)
    ElMessage.success(t('admin.roleDeleted'))
    await reloadRoles()
  } catch (e) {
    ElMessage.error(errorMessage(e))
  }
}

// ------------------------------------------------------------------ matrix

const matrixSaving = ref(false)

/**
 * Ticking a box stores the role's whole permission set straight away, which is
 * what makes the change reach open sessions (PS-111 AC3). The role comes back
 * from the server, so a row can never drift from what was actually stored.
 */
async function togglePermission(role: AdminRole, permission: AdminPermission, checked: boolean) {
  if (matrixSaving.value || role.roleType !== CUSTOM) return
  const next = new Set(role.permissionIds)
  if (checked) {
    next.add(permission.permissionId)
  } else {
    next.delete(permission.permissionId)
  }
  matrixSaving.value = true
  try {
    const updated = await adminApi.setRolePermissions(role.roleId, [...next])
    const index = roles.value.findIndex((r) => r.roleId === role.roleId)
    if (index >= 0) roles.value[index] = updated
    ElMessage.success(t('admin.matrixSaved'))
  } catch (e) {
    ElMessage.error(errorMessage(e))
  } finally {
    matrixSaving.value = false
  }
}

function saveBlob(blob: Blob, fileName: string) {
  const url = window.URL.createObjectURL(blob)
  const link = document.createElement('a')
  link.href = url
  link.download = fileName
  document.body.appendChild(link)
  link.click()
  document.body.removeChild(link)
  window.URL.revokeObjectURL(url)
}

async function exportMatrix() {
  try {
    saveBlob(await adminApi.exportMatrix(), 'permission-matrix.xlsx')
    ElMessage.success(t('admin.exportDone'))
  } catch (e) {
    ElMessage.error(t('admin.matrixExportFailed') + errorMessage(e))
  }
}

onMounted(load)
</script>

<template>
  <div v-loading="loading">
    <div class="page-head">
      <div class="page-title-row">
        <div>
          <h1 class="page-title">{{ t('page.admin') }}</h1>
          <div class="page-sub">{{ t('admin.sub') }}</div>
        </div>
      </div>
    </div>

    <el-tabs v-model="activeTab" type="border-card" data-admin-tabs>
      <!-- ================================================= users -->
      <el-tab-pane :label="t('admin.tabUsers')" name="users">
        <div class="card">
          <div class="card-head">
            <div>
              <div class="card-title">{{ t('admin.userList') }}</div>
              <div class="card-sub" data-admin-user-count>
                {{ t('admin.userTotal', { n: filteredUsers.length }) }}
              </div>
            </div>
            <div class="card-head-actions">
              <span data-admin-user-search>
                <el-input
                  v-model="userKeyword"
                  :placeholder="t('admin.searchPlaceholder')"
                  clearable
                  style="width: 240px"
                />
              </span>
            </div>
          </div>

          <div class="card-body flush">
            <el-table :data="filteredUsers" row-key="employeeId" data-admin-users>
              <el-table-column :label="t('admin.colEmployee')" min-width="150">
                <template #default="{ row }">
                  <div class="cell-stack">
                    <span class="t-1 fw-medium">{{ row.name }}</span>
                    <span class="mono fs-11 t-3">{{ row.employeeId }}</span>
                  </div>
                </template>
              </el-table-column>

              <el-table-column :label="t('admin.colDept')" min-width="150">
                <template #default="{ row }">
                  <span class="fs-12 t-2">{{ department(row) }}</span>
                </template>
              </el-table-column>

              <el-table-column :label="t('admin.colJob')" min-width="120">
                <template #default="{ row }">
                  <span class="fs-12 t-2">{{ row.jobTitle || '—' }}</span>
                </template>
              </el-table-column>

              <el-table-column :label="t('admin.colAccount')" min-width="170">
                <template #default="{ row }">
                  <div class="cell-stack">
                    <span class="mono fs-12 t-2">{{ row.username || '—' }}</span>
                    <span class="badge-row">
                      <span
                        v-for="badge in accountBadges(row)"
                        :key="badge.label"
                        :class="badge.cls"
                        data-admin-account-state
                        >{{ badge.label }}</span
                      >
                    </span>
                  </div>
                </template>
              </el-table-column>

              <el-table-column :label="t('admin.colRoles')" min-width="200">
                <template #default="{ row }">
                  <span v-if="!row.roleCodes.length" class="fs-12 t-3">{{ t('admin.noRoles') }}</span>
                  <span v-else class="badge-row">
                    <span
                      v-for="code in row.roleCodes"
                      :key="code"
                      class="badge badge-neutral"
                      data-admin-user-role
                      >{{ roleLabel(code) }}</span
                    >
                  </span>
                </template>
              </el-table-column>

              <el-table-column v-if="canManage" :label="t('common.actions')" width="150">
                <template #default="{ row }">
                  <span class="row-acts">
                    <RowAction
                      act="assign"
                      icon="user"
                      :label="t('admin.assignRoles')"
                      @click="openAssign(row)"
                    />
                    <RowAction
                      v-if="row.accountActive !== null"
                      :act="row.accountActive ? 'disable' : 'enable'"
                      :icon="row.accountActive ? 'arrowRightFromLine' : 'check'"
                      :tone="row.accountActive ? 'warning' : undefined"
                      :label="
                        row.accountActive ? t('admin.deactivateAccount') : t('admin.activateAccount')
                      "
                      @click="toggleAccount(row)"
                    />
                    <RowAction
                      v-if="row.accountActive !== null"
                      act="reset"
                      icon="key"
                      :label="t('admin.resetPassword')"
                      @click="openReset(row)"
                    />
                    <RowAction
                      v-if="row.locked"
                      act="unlock"
                      icon="lock"
                      :label="t('admin.unlock')"
                      @click="unlockAccount(row)"
                    />
                  </span>
                </template>
              </el-table-column>

              <template #empty>
                <div class="empty">
                  <div class="empty-art"><QmsIcon name="user" :size="26" /></div>
                  <div class="empty-title">{{ t('admin.emptyUsers') }}</div>
                  <div class="empty-text">{{ t('admin.emptyUsersText') }}</div>
                </div>
              </template>
            </el-table>
          </div>
        </div>
      </el-tab-pane>

      <!-- ================================================= roles -->
      <el-tab-pane :label="t('admin.tabRoles')" name="roles">
        <div class="card">
          <div class="card-head">
            <div>
              <div class="card-title">{{ t('admin.tabRoles') }}</div>
              <div class="card-sub" data-admin-role-count>
                {{ t('admin.roleTotal', { n: roles.length }) }}
              </div>
            </div>
            <div v-if="canManage" class="card-head-actions">
              <el-button type="primary" data-admin-role-new @click="openNewRole">
                <QmsIcon name="plus" :size="14" />
                <span>{{ t('admin.newRole') }}</span>
              </el-button>
            </div>
          </div>

          <div class="card-body flush">
            <el-table :data="roles" row-key="roleId" data-admin-roles>
              <el-table-column :label="t('admin.colRoleName')" min-width="180">
                <template #default="{ row }">
                  <div class="cell-stack">
                    <span class="t-1 fw-medium" data-admin-role-name>{{ row.roleName }}</span>
                    <span v-if="row.roleNameEn" class="fs-11 t-3">{{ row.roleNameEn }}</span>
                  </div>
                </template>
              </el-table-column>

              <el-table-column :label="t('admin.colRoleCode')" min-width="170">
                <template #default="{ row }">
                  <span class="mono fs-12 t-3">{{ row.roleCode }}</span>
                </template>
              </el-table-column>

              <el-table-column :label="t('admin.colRoleType')" width="90">
                <template #default="{ row }">
                  <span
                    :class="row.roleType === PRESET ? 'badge badge-neutral' : 'badge badge-info'"
                    data-admin-role-type
                  >
                    {{
                      row.roleType === PRESET ? t('admin.roleTypePreset') : t('admin.roleTypeCustom')
                    }}
                  </span>
                </template>
              </el-table-column>

              <el-table-column :label="t('admin.colRoleStatus')" width="90">
                <template #default="{ row }">
                  <span
                    :class="row.isActive ? 'badge badge-success' : 'badge badge-warning'"
                    data-admin-role-status
                  >
                    {{ row.isActive ? t('admin.statusActive') : t('admin.statusInactive') }}
                  </span>
                </template>
              </el-table-column>

              <el-table-column :label="t('admin.colRoleCount')" width="96" align="right">
                <template #default="{ row }">
                  <span class="mono fs-12 t-2" data-admin-role-users>{{ row.userCount }}</span>
                </template>
              </el-table-column>

              <el-table-column :label="t('admin.colPermCount')" width="96" align="right">
                <template #default="{ row }">
                  <span class="mono fs-12 t-2" data-admin-role-perms>{{
                    row.permissionIds.length
                  }}</span>
                </template>
              </el-table-column>

              <el-table-column v-if="canManage" :label="t('common.actions')" width="150">
                <template #default="{ row }">
                  <span class="row-acts">
                    <RowAction
                      v-if="row.roleType === CUSTOM"
                      act="rename"
                      icon="pencil"
                      :label="t('admin.rename')"
                      @click="openRename(row)"
                    />
                    <RowAction
                      act="copy"
                      icon="copy"
                      :label="t('admin.copyRole')"
                      @click="copyRole(row)"
                    />
                    <RowAction
                      v-if="row.roleType === CUSTOM"
                      :act="row.isActive ? 'disable-role' : 'enable-role'"
                      :icon="row.isActive ? 'arrowRightFromLine' : 'check'"
                      :tone="row.isActive ? 'warning' : undefined"
                      :label="row.isActive ? t('admin.deactivateRole') : t('admin.activateRole')"
                      @click="toggleRole(row)"
                    />
                    <RowAction
                      v-if="row.roleType === CUSTOM"
                      act="delete-role"
                      icon="trash"
                      tone="danger"
                      :label="t('admin.deleteRole')"
                      @click="removeRole(row)"
                    />
                  </span>
                </template>
              </el-table-column>

              <template #empty>
                <div class="empty">
                  <div class="empty-art"><QmsIcon name="settings" :size="26" /></div>
                  <div class="empty-title">{{ t('admin.emptyRoles') }}</div>
                  <div class="empty-text">{{ t('admin.emptyRolesText') }}</div>
                </div>
              </template>
            </el-table>
          </div>
        </div>
      </el-tab-pane>

      <!-- ================================================= matrix -->
      <el-tab-pane :label="t('admin.tabMatrix')" name="matrix">
        <div class="card">
          <div class="card-head">
            <div>
              <div class="card-title">{{ t('admin.tabMatrix') }}</div>
              <div class="card-sub">{{ t('admin.matrixHint') }}</div>
            </div>
            <div class="card-head-actions">
              <el-button data-admin-export @click="exportMatrix">
                <QmsIcon name="download" :size="14" />
                <span>{{ t('admin.exportMatrix') }}</span>
              </el-button>
            </div>
          </div>

          <div class="card-body flush">
            <el-table
              :data="permissions"
              row-key="permissionId"
              :span-method="spanMethod"
              border
              data-admin-matrix
            >
              <el-table-column :label="t('admin.colPermModule')" width="120">
                <template #default="{ row }">
                  <span class="fs-12 fw-medium t-2" data-admin-matrix-module>{{
                    moduleLabel(row.moduleCode)
                  }}</span>
                </template>
              </el-table-column>

              <el-table-column :label="t('admin.colPermName')" min-width="220">
                <template #default="{ row }">
                  <div class="cell-stack">
                    <span class="fs-13 t-1">{{ permissionLabel(row) }}</span>
                    <span class="mono fs-11 t-3">{{ row.permissionCode }}</span>
                  </div>
                </template>
              </el-table-column>

              <el-table-column :label="t('admin.colPermLevel')" width="110">
                <template #default="{ row }">
                  <span class="fs-12 t-3">{{ levelLabel(row.permissionLevel) }}</span>
                </template>
              </el-table-column>

              <el-table-column v-for="role in roles" :key="role.roleId" width="112" align="center">
                <template #header>
                  <span
                    class="mx-head"
                    :class="{ 'is-preset': role.roleType === PRESET }"
                    :data-role-col="role.roleId"
                    >{{ role.roleName }}</span
                  >
                </template>
                <template #default="{ row }">
                  <div class="mx-cell" :data-perm-cell="role.roleId + ':' + row.permissionId">
                    <el-checkbox
                      :model-value="role.permissionIds.includes(row.permissionId)"
                      :disabled="role.roleType !== CUSTOM || matrixSaving"
                      @change="(value: string | number | boolean) => togglePermission(role, row, !!value)"
                    />
                  </div>
                </template>
              </el-table-column>
            </el-table>
          </div>
        </div>
      </el-tab-pane>

      <!-- ============================================ master data -->
      <el-tab-pane :label="t('admin.tabMasterData')" name="masterdata">
        <MasterDataPanel />
      </el-tab-pane>

      <!-- ============================================ failure types -->
      <el-tab-pane :label="t('admin.tabFailureType')" name="failureTypes">
        <FailureTypePanel />
      </el-tab-pane>
    </el-tabs>

    <!-- assign roles -->
    <el-dialog
      v-model="assignOpen"
      :title="t('admin.assignTitle', { name: assignTarget?.name ?? '' })"
      width="520px"
      destroy-on-close
    >
      <div class="fs-12 t-3 mb-3">{{ t('admin.assignHint') }}</div>
      <div data-admin-assign-field>
        <el-select v-model="assignSelection" multiple style="width: 100%">
          <el-option
            v-for="role in roles"
            :key="role.roleCode"
            :label="role.roleName"
            :value="role.roleCode"
            :disabled="!role.isActive"
          >
            <span class="ad-opt">
              <span>{{ role.roleName }}</span>
              <span class="fs-11 t-3">{{ role.isActive ? '' : t('admin.statusInactive') }}</span>
            </span>
          </el-option>
        </el-select>
      </div>
      <div v-if="assignDropped.length" class="fs-11 t-3 mt-2">
        {{ t('admin.assignInactiveHint') }} ({{ assignDropped.join(' / ') }})
      </div>
      <template #footer>
        <el-button @click="assignOpen = false">{{ t('common.cancel') }}</el-button>
        <el-button type="primary" :loading="assignSaving" data-admin-assign-save @click="saveAssign">
          {{ t('common.save') }}
        </el-button>
      </template>
    </el-dialog>

    <!-- reset password -->
    <el-dialog
      v-model="resetOpen"
      :title="t('admin.resetTitle', { name: resetTarget?.name ?? '' })"
      width="480px"
      destroy-on-close
    >
      <div class="fs-12 t-3 mb-3">{{ t('admin.resetHint') }}</div>
      <el-form label-width="96px" label-position="left">
        <el-form-item :label="t('admin.resetNewPassword')" required>
          <div class="ad-field" data-admin-reset-field>
            <el-input v-model="resetPassword" type="password" show-password maxlength="72" />
          </div>
        </el-form-item>
      </el-form>
      <template #footer>
        <el-button @click="resetOpen = false">{{ t('common.cancel') }}</el-button>
        <el-button type="primary" :loading="resetSaving" data-admin-reset-save @click="saveReset">
          {{ t('common.save') }}
        </el-button>
      </template>
    </el-dialog>

    <!-- create / rename role -->
    <el-dialog
      v-model="roleOpen"
      :title="editingRoleId == null ? t('admin.newRole') : t('admin.editRole')"
      width="480px"
      destroy-on-close
    >
      <el-form label-width="110px" label-position="left">
        <el-form-item :label="t('admin.roleName')" required>
          <div class="ad-field" data-admin-role-field-name>
            <el-input v-model="roleForm.roleName" maxlength="64" />
          </div>
        </el-form-item>
        <el-form-item :label="t('admin.roleNameEn')">
          <div class="ad-field" data-admin-role-field-name-en>
            <el-input v-model="roleForm.roleNameEn" maxlength="64" />
          </div>
        </el-form-item>
      </el-form>
      <template #footer>
        <el-button @click="roleOpen = false">{{ t('common.cancel') }}</el-button>
        <el-button type="primary" :loading="roleSaving" data-admin-role-save @click="saveRole">
          {{ t('common.save') }}
        </el-button>
      </template>
    </el-dialog>
  </div>
</template>

<style scoped>
.cell-stack {
  display: flex;
  flex-direction: column;
  gap: 2px;
  min-width: 0;
}

.badge-row {
  display: inline-flex;
  flex-wrap: wrap;
  gap: 4px;
}

/* Fills the form-item column, and anchors the UI script: Element Plus forwards
   fallthrough attributes onto the inner <input>, so the control itself is not a
   reliable hook. */
.ad-field {
  width: 100%;
}

.ad-opt {
  display: flex;
  justify-content: space-between;
  gap: var(--sp-3);
}

/* A preset role's permissions are fixed; a muted header says so at a glance. */
.mx-head.is-preset {
  color: var(--t-3);
}

.mx-cell {
  display: inline-flex;
  justify-content: center;
}
</style>
