<script setup lang="ts">
import { computed, onMounted, reactive, ref } from 'vue'
import { useI18n } from 'vue-i18n'
import { ElMessage, ElMessageBox } from 'element-plus'
import { errorMessage } from '@/api/http'
import { masterDataAdminApi, type FailureTypeNode } from '@/api/masterDataAdmin'
import { useAuthStore } from '@/stores/auth'
import { useMetaStore } from '@/stores/meta'
import QmsIcon from '@/components/QmsIcon.vue'
import RowAction from '@/components/RowAction.vue'

/**
 * The three-level failure type tree (PS-036): L1 / L2 / L3, codes built as
 * 2 -> 2a -> 2aa.
 *
 * The code carries the level, and business rows reference it by foreign key, so
 * a node's code and parent are fixed once created -- what moves is the name and
 * the active flag. A node built at the wrong level is deleted and rebuilt, which
 * is what "level adjustment" comes to when the code is the level.
 *
 * Deactivating a node takes its descendants with it; a node cannot come back
 * before its parent does, so no picker can ever offer an unreachable entry.
 */
const { t } = useI18n()
const auth = useAuthStore()
const meta = useMetaStore()

const canManage = computed(() => auth.can('masterdata:manage'))

const tree = ref<FailureTypeNode[]>([])
const loading = ref(false)

/** Next free code, so the convention does not have to be remembered by hand. */
const ROOT_CHARS = '123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ'
const CHILD_CHARS = 'abcdefghijklmnopqrstuvwxyz0123456789'

function countNodes(nodes: FailureTypeNode[]): number {
  return nodes.reduce((total, node) => total + 1 + countNodes(node.children ?? []), 0)
}

const total = computed(() => countNodes(tree.value))

function levelLabel(levelNo: number): string {
  return t(`admin.ftLevel${levelNo}`)
}

function suggestRootCode(): string {
  const used = new Set(tree.value.map((node) => node.code))
  for (const ch of ROOT_CHARS) {
    if (!used.has(ch)) return ch
  }
  return ''
}

function suggestChildCode(parent: FailureTypeNode): string {
  const used = new Set((parent.children ?? []).map((node) => node.code))
  for (const ch of CHILD_CHARS) {
    const candidate = parent.code + ch
    if (!used.has(candidate)) return candidate
  }
  return parent.code
}

async function load() {
  loading.value = true
  try {
    tree.value = await masterDataAdminApi.failureTypeTree()
  } catch (e) {
    ElMessage.error(t('admin.ftLoadFailed') + errorMessage(e))
  } finally {
    loading.value = false
  }
}

/** Every write goes through here, so the cascade pickers never keep stale values. */
async function afterWrite() {
  await load()
  await meta.refresh()
}

// ------------------------------------------------------------------ dialog

const dialogOpen = ref(false)
/** Non-null means renaming; the code and the parent are then fixed. */
const editingCode = ref<string | null>(null)
const parentLabel = ref('')
const saving = ref(false)
const form = reactive({ parentCode: null as string | null, code: '', name: '' })

function openNewRoot() {
  editingCode.value = null
  parentLabel.value = ''
  Object.assign(form, { parentCode: null, code: suggestRootCode(), name: '' })
  dialogOpen.value = true
}

function openNewChild(parent: FailureTypeNode) {
  editingCode.value = null
  parentLabel.value = `${parent.code} ${parent.name}`
  Object.assign(form, { parentCode: parent.code, code: suggestChildCode(parent), name: '' })
  dialogOpen.value = true
}

function openRename(node: FailureTypeNode) {
  editingCode.value = node.code
  parentLabel.value = ''
  Object.assign(form, { parentCode: null, code: node.code, name: node.name })
  dialogOpen.value = true
}

async function save() {
  if (editingCode.value == null && !form.code.trim()) {
    ElMessage.warning(t('admin.ftCodeRequired'))
    return
  }
  if (!form.name.trim()) {
    ElMessage.warning(t('admin.ftNameRequired'))
    return
  }
  saving.value = true
  try {
    if (editingCode.value == null) {
      await masterDataAdminApi.createFailureType({
        parentCode: form.parentCode,
        code: form.code.trim(),
        name: form.name.trim()
      })
      ElMessage.success(t('admin.ftCreated'))
    } else {
      await masterDataAdminApi.renameFailureType(editingCode.value, { name: form.name.trim() })
      ElMessage.success(t('admin.ftSaved'))
    }
    dialogOpen.value = false
    await afterWrite()
  } catch (e) {
    ElMessage.error(errorMessage(e))
  } finally {
    saving.value = false
  }
}

// ---------------------------------------------------------------- row actions

function confirmThen(message: string, title: string): Promise<boolean> {
  return ElMessageBox.confirm(message, title, {
    type: 'warning',
    confirmButtonText: t('common.confirm'),
    cancelButtonText: t('common.cancel')
  })
    .then(() => true)
    .catch(() => false)
}

async function toggleActive(node: FailureTypeNode) {
  const enabling = !node.active
  const ok = await confirmThen(
    t('admin.ftStatusConfirm', {
      action: enabling ? t('admin.ftActivate') : t('admin.ftDeactivate'),
      name: node.name
    }) + (enabling ? '' : ' ' + t('admin.ftDeactivateWarn')),
    enabling ? t('admin.ftActivate') : t('admin.ftDeactivate')
  )
  if (!ok) return
  try {
    if (enabling) {
      await masterDataAdminApi.activateFailureType(node.code)
    } else {
      await masterDataAdminApi.deactivateFailureType(node.code)
    }
    ElMessage.success(t('admin.ftStatusChanged'))
    await afterWrite()
  } catch (e) {
    ElMessage.error(errorMessage(e))
  }
}

async function remove(node: FailureTypeNode) {
  const ok = await confirmThen(
    t('admin.ftDeleteConfirm', { name: node.name }),
    t('admin.ftDelete')
  )
  if (!ok) return
  try {
    await masterDataAdminApi.deleteFailureType(node.code)
    ElMessage.success(t('admin.ftDeleted'))
    await afterWrite()
  } catch (e) {
    ElMessage.error(errorMessage(e))
  }
}

onMounted(load)
</script>

<template>
  <div class="card">
    <div class="card-head">
      <div>
        <div class="card-title">{{ t('admin.ftTitle') }}</div>
        <div class="card-sub" data-ft-count>{{ t('admin.ftTotal', { n: total }) }}</div>
      </div>
      <div v-if="canManage" class="card-head-actions">
        <el-button type="primary" data-ft-new-root @click="openNewRoot">
          <QmsIcon name="plus" :size="14" />
          <span>{{ t('admin.ftNewRoot') }}</span>
        </el-button>
      </div>
    </div>

    <div class="card-body flush" v-loading="loading">
      <el-table
        :data="tree"
        row-key="id"
        :tree-props="{ children: 'children' }"
        default-expand-all
        data-ft-table
      >
        <el-table-column :label="t('admin.ftColCode')" width="150">
          <template #default="{ row }">
            <span class="mono fs-12 t-2" :data-ft-row="row.code">{{ row.code }}</span>
          </template>
        </el-table-column>

        <el-table-column :label="t('admin.ftColName')" min-width="280">
          <template #default="{ row }">
            <span class="t-1" :data-ft-name="row.code">{{ row.name }}</span>
          </template>
        </el-table-column>

        <el-table-column :label="t('admin.ftColLevel')" width="80">
          <template #default="{ row }">
            <span class="badge badge-neutral" data-ft-level>{{ levelLabel(row.levelNo) }}</span>
          </template>
        </el-table-column>

        <el-table-column :label="t('admin.ftColStatus')" width="86">
          <template #default="{ row }">
            <span
              :class="row.active ? 'badge badge-success' : 'badge badge-warning'"
              data-ft-status
            >
              {{ row.active ? t('admin.statusActive') : t('admin.statusInactive') }}
            </span>
          </template>
        </el-table-column>

        <el-table-column v-if="canManage" :label="t('common.actions')" width="150">
          <template #default="{ row }">
            <span class="row-acts">
              <RowAction
                v-if="row.levelNo < 3 && row.active"
                act="ft-add-child"
                icon="plus"
                :label="t('admin.ftNewChild')"
                @click="openNewChild(row)"
              />
              <RowAction
                act="ft-rename"
                icon="pencil"
                :label="t('admin.ftRename')"
                @click="openRename(row)"
              />
              <RowAction
                :act="row.active ? 'ft-disable' : 'ft-enable'"
                :icon="row.active ? 'arrowRightFromLine' : 'check'"
                :tone="row.active ? 'warning' : undefined"
                :label="row.active ? t('admin.ftDeactivate') : t('admin.ftActivate')"
                @click="toggleActive(row)"
              />
              <RowAction
                act="ft-delete"
                icon="trash"
                tone="danger"
                :label="t('admin.ftDelete')"
                @click="remove(row)"
              />
            </span>
          </template>
        </el-table-column>

        <template #empty>
          <div class="empty" data-ft-empty>
            <div class="empty-art"><QmsIcon name="settings" :size="26" /></div>
            <div class="empty-title">{{ t('admin.ftEmptyTitle') }}</div>
            <div class="empty-text">{{ t('admin.ftEmptyText') }}</div>
          </div>
        </template>
      </el-table>
    </div>

    <el-dialog
      v-model="dialogOpen"
      :title="
        editingCode == null
          ? form.parentCode == null
            ? t('admin.ftNewRoot')
            : t('admin.ftNewChildTitle', { parent: parentLabel })
          : t('admin.ftRenameTitle', { code: editingCode })
      "
      width="520px"
      destroy-on-close
    >
      <el-form label-width="96px" label-position="left">
        <el-form-item :label="t('admin.ftColCode')" required>
          <div class="ft-field" data-ft-field-code>
            <el-input
              v-model="form.code"
              maxlength="32"
              :disabled="editingCode != null"
              :placeholder="t('admin.ftCodeHint')"
            />
          </div>
        </el-form-item>
        <div v-if="editingCode == null" class="fs-11 t-3 ft-hint">
          {{ t('admin.ftCodeRule') }}
        </div>

        <el-form-item :label="t('admin.ftColName')" required>
          <div class="ft-field" data-ft-field-name>
            <el-input v-model="form.name" maxlength="128" />
          </div>
        </el-form-item>

        <div v-if="editingCode != null" class="fs-11 t-3 ft-hint">
          {{ t('admin.ftCodeImmutable') }}
        </div>
      </el-form>
      <template #footer>
        <el-button @click="dialogOpen = false">{{ t('common.cancel') }}</el-button>
        <el-button type="primary" :loading="saving" data-ft-save @click="save">
          {{ t('common.save') }}
        </el-button>
      </template>
    </el-dialog>
  </div>
</template>

<style scoped>
/* Fills the form column, and anchors the UI script: Element Plus forwards
   fallthrough attributes onto the inner <input>, so the control itself is not a
   reliable hook. */
.ft-field {
  width: 100%;
}

.ft-hint {
  margin: -8px 0 var(--sp-3) 96px;
}
</style>
