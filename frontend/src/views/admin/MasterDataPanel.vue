<script setup lang="ts">
import { computed, onMounted, reactive, ref } from 'vue'
import { useI18n } from 'vue-i18n'
import { ElMessage, ElMessageBox } from 'element-plus'
import { errorMessage } from '@/api/http'
import { masterDataAdminApi, type DictionaryEntry, type DictionaryType } from '@/api/masterDataAdmin'
import { useAuthStore } from '@/stores/auth'
import { useMetaStore } from '@/stores/meta'
import QmsIcon from '@/components/QmsIcon.vue'
import RowAction from '@/components/RowAction.vue'

/**
 * The platform's own reference data (PS-109): complaint types, failure locations,
 * failure modes and the rest, grouped by type.
 *
 * The codes are business keys -- business rows reference them by foreign key --
 * so a code is set once and never changes; only the names, the sort order and the
 * active flag move. Deleting is offered because a mistyped code would otherwise
 * live forever, and it is allowed only while nothing depends on the entry.
 *
 * The priority list is read-only: its target days come from the server config, so
 * a new code there would silently mean "14 days" with nothing on screen to say so.
 */
const { t, te } = useI18n()
const auth = useAuthStore()
const meta = useMetaStore()

const canManage = computed(() => auth.can('masterdata:manage'))

const types = ref<DictionaryType[]>([])
const activeType = ref('')
const items = ref<DictionaryEntry[]>([])
const keyword = ref('')
const loading = ref(false)

const currentType = computed(() => types.value.find((x) => x.mdType === activeType.value))
const editable = computed(() => currentType.value?.editable !== false)
const canWrite = computed(() => canManage.value && editable.value)

const filtered = computed(() => {
  const kw = keyword.value.trim().toLowerCase()
  if (!kw) return items.value
  return items.value.filter((i) =>
    [i.code, i.nameCn, i.nameEn].some((v) => (v ?? '').toLowerCase().includes(kw))
  )
})

/** The display name of a type falls back to its code when no translation exists. */
function typeLabel(mdType: string): string {
  return te(`admin.mdType.${mdType}`) ? t(`admin.mdType.${mdType}`) : mdType
}

async function loadTypes() {
  try {
    types.value = await masterDataAdminApi.dictionaryTypes()
    if (!activeType.value && types.value.length) {
      activeType.value = types.value[0].mdType
    }
  } catch (e) {
    ElMessage.error(t('admin.mdLoadFailed') + errorMessage(e))
  }
}

async function loadItems() {
  if (!activeType.value) return
  loading.value = true
  try {
    items.value = await masterDataAdminApi.items(activeType.value)
  } catch (e) {
    ElMessage.error(t('admin.mdLoadFailed') + errorMessage(e))
  } finally {
    loading.value = false
  }
}

async function loadAll() {
  await loadTypes()
  await loadItems()
}

function selectType(mdType: string) {
  activeType.value = mdType
  keyword.value = ''
  loadItems()
}

/** Every write goes through here, so the pickers never keep stale values. */
async function afterWrite() {
  await loadTypes()
  await loadItems()
  await meta.refresh()
}

// ------------------------------------------------------------------ dialog

const dialogOpen = ref(false)
const editingCode = ref<string | null>(null)
const saving = ref(false)
const form = reactive({ code: '', nameCn: '', nameEn: '', sortOrder: null as number | null })

function openNew() {
  editingCode.value = null
  Object.assign(form, { code: '', nameCn: '', nameEn: '', sortOrder: null })
  dialogOpen.value = true
}

function openEdit(row: DictionaryEntry) {
  editingCode.value = row.code
  Object.assign(form, {
    code: row.code,
    nameCn: row.nameCn,
    nameEn: row.nameEn ?? '',
    sortOrder: row.sortOrder ?? null
  })
  dialogOpen.value = true
}

async function save() {
  if (editingCode.value == null && !form.code.trim()) {
    ElMessage.warning(t('admin.mdCodeRequired'))
    return
  }
  if (!form.nameCn.trim()) {
    ElMessage.warning(t('admin.mdNameRequired'))
    return
  }
  saving.value = true
  try {
    if (editingCode.value == null) {
      await masterDataAdminApi.createItem(activeType.value, {
        code: form.code.trim(),
        nameCn: form.nameCn.trim(),
        nameEn: form.nameEn.trim() || null,
        sortOrder: form.sortOrder
      })
      ElMessage.success(t('admin.mdCreated'))
    } else {
      await masterDataAdminApi.updateItem(activeType.value, editingCode.value, {
        nameCn: form.nameCn.trim(),
        nameEn: form.nameEn.trim() || null,
        sortOrder: form.sortOrder
      })
      ElMessage.success(t('admin.mdSaved'))
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

async function toggleActive(row: DictionaryEntry) {
  const enabling = !row.active
  const ok = await confirmThen(
    t('admin.mdStatusConfirm', {
      action: enabling ? t('admin.mdActivate') : t('admin.mdDeactivate'),
      name: row.nameCn
    }) + (enabling ? '' : ' ' + t('admin.mdDeactivateWarn')),
    enabling ? t('admin.mdActivate') : t('admin.mdDeactivate')
  )
  if (!ok) return
  try {
    if (enabling) {
      await masterDataAdminApi.activateItem(activeType.value, row.code)
    } else {
      await masterDataAdminApi.deactivateItem(activeType.value, row.code)
    }
    ElMessage.success(t('admin.mdStatusChanged'))
    await afterWrite()
  } catch (e) {
    ElMessage.error(errorMessage(e))
  }
}

async function remove(row: DictionaryEntry) {
  const ok = await confirmThen(
    t('admin.mdDeleteConfirm', { name: row.nameCn }),
    t('admin.mdDelete')
  )
  if (!ok) return
  try {
    await masterDataAdminApi.deleteItem(activeType.value, row.code)
    ElMessage.success(t('admin.mdDeleted'))
    await afterWrite()
  } catch (e) {
    ElMessage.error(errorMessage(e))
  }
}

onMounted(loadAll)
</script>

<template>
  <div class="card">
    <div class="card-head">
      <div>
        <div class="card-title">{{ t('admin.mdTitle') }}</div>
        <div class="card-sub" data-md-count>
          {{ t('admin.mdTotal', { n: filtered.length }) }}
        </div>
      </div>
      <div class="card-head-actions">
        <span data-md-search>
          <el-input
            v-model="keyword"
            :placeholder="t('admin.mdSearch')"
            clearable
            style="width: 220px"
          />
        </span>
        <el-button v-if="canWrite" type="primary" data-md-new @click="openNew">
          <QmsIcon name="plus" :size="14" />
          <span>{{ t('admin.mdNew') }}</span>
        </el-button>
      </div>
    </div>

    <div class="card-body md-body">
      <!-- the type list -->
      <aside class="md-types" data-md-types>
        <button
          v-for="type in types"
          :key="type.mdType"
          class="menu-item"
          :class="{ 'is-on': activeType === type.mdType }"
          :data-md-type="type.mdType"
          @click="selectType(type.mdType)"
        >
          <span class="grow">{{ typeLabel(type.mdType) }}</span>
          <span class="count-pill">{{ type.active }}/{{ type.total }}</span>
        </button>
      </aside>

      <!-- the entries of the selected type -->
      <div class="md-list" v-loading="loading">
        <div v-if="!editable" class="md-readonly fs-12" data-md-readonly>
          {{ t('admin.mdReadonly') }}
        </div>

        <el-table :data="filtered" row-key="id" data-md-table>
          <el-table-column :label="t('admin.mdColCode')" width="210">
            <template #default="{ row }">
              <span class="mono fs-12 t-2 md-code" :data-md-row="row.code" :title="row.code">{{
                row.code
              }}</span>
            </template>
          </el-table-column>

          <el-table-column :label="t('admin.mdColNameCn')" min-width="150">
            <template #default="{ row }">
              <span class="t-1">{{ row.nameCn }}</span>
            </template>
          </el-table-column>

          <el-table-column :label="t('admin.mdColNameEn')" min-width="150">
            <template #default="{ row }">
              <span class="fs-12 t-2">{{ row.nameEn || '—' }}</span>
            </template>
          </el-table-column>

          <el-table-column :label="t('admin.mdColSort')" width="64" align="right">
            <template #default="{ row }">
              <span class="mono fs-12 t-3" data-md-sort>{{ row.sortOrder ?? '—' }}</span>
            </template>
          </el-table-column>

          <el-table-column :label="t('admin.mdColSource')" width="72">
            <template #default="{ row }">
              <span class="fs-11 t-3">{{ row.sourceSystem }}</span>
            </template>
          </el-table-column>

          <el-table-column :label="t('admin.mdColStatus')" width="80">
            <template #default="{ row }">
              <span
                :class="row.active ? 'badge badge-success' : 'badge badge-warning'"
                data-md-status
              >
                {{ row.active ? t('admin.statusActive') : t('admin.statusInactive') }}
              </span>
            </template>
          </el-table-column>

          <el-table-column v-if="canWrite" :label="t('common.actions')" width="122">
            <template #default="{ row }">
              <span class="row-acts">
                <RowAction
                  act="md-edit"
                  icon="pencil"
                  :label="t('admin.mdEdit')"
                  @click="openEdit(row)"
                />
                <RowAction
                  :act="row.active ? 'md-disable' : 'md-enable'"
                  :icon="row.active ? 'arrowRightFromLine' : 'check'"
                  :tone="row.active ? 'warning' : undefined"
                  :label="row.active ? t('admin.mdDeactivate') : t('admin.mdActivate')"
                  @click="toggleActive(row)"
                />
                <RowAction
                  act="md-delete"
                  icon="trash"
                  tone="danger"
                  :label="t('admin.mdDelete')"
                  @click="remove(row)"
                />
              </span>
            </template>
          </el-table-column>

          <template #empty>
            <div class="empty" data-md-empty>
              <div class="empty-art"><QmsIcon name="list" :size="26" /></div>
              <div class="empty-title">{{ t('admin.mdEmptyTitle') }}</div>
              <div class="empty-text">{{ t('admin.mdEmptyText') }}</div>
            </div>
          </template>
        </el-table>
      </div>
    </div>

    <el-dialog
      v-model="dialogOpen"
      :title="
        editingCode == null
          ? t('admin.mdNewTitle', { type: typeLabel(activeType) })
          : t('admin.mdEditTitle', { code: editingCode })
      "
      width="520px"
      destroy-on-close
    >
      <el-form label-width="96px" label-position="left">
        <el-form-item :label="t('admin.mdColCode')" required>
          <div class="md-field" data-md-field-code>
            <el-input
              v-model="form.code"
              maxlength="32"
              :disabled="editingCode != null"
              :placeholder="editingCode == null ? t('admin.mdCodeHint') : ''"
            />
          </div>
        </el-form-item>
        <div v-if="editingCode != null" class="fs-11 t-3 md-hint">
          {{ t('admin.mdCodeImmutable') }}
        </div>

        <el-form-item :label="t('admin.mdColNameCn')" required>
          <div class="md-field" data-md-field-name>
            <el-input v-model="form.nameCn" maxlength="128" />
          </div>
        </el-form-item>

        <el-form-item :label="t('admin.mdColNameEn')">
          <div class="md-field" data-md-field-name-en>
            <el-input v-model="form.nameEn" maxlength="128" />
          </div>
        </el-form-item>

        <el-form-item :label="t('admin.mdColSort')">
          <div class="md-field" data-md-field-sort>
            <el-input-number v-model="form.sortOrder" :min="1" :max="9999" controls-position="right" />
          </div>
        </el-form-item>
      </el-form>
      <template #footer>
        <el-button @click="dialogOpen = false">{{ t('common.cancel') }}</el-button>
        <el-button type="primary" :loading="saving" data-md-save @click="save">
          {{ t('common.save') }}
        </el-button>
      </template>
    </el-dialog>
  </div>
</template>

<style scoped>
/*
  A type list beside the entries. The shared .grid-sidebar stacks below 1280px,
  which would push the type list under the table -- the same trade the knowledge
  centre makes, so this page keeps its own narrow two-column grid instead.
*/
.md-body {
  display: grid;
  grid-template-columns: 220px minmax(0, 1fr);
  gap: var(--sp-4);
  align-items: start;
}

@media (max-width: 1100px) {
  .md-body {
    grid-template-columns: minmax(0, 1fr);
  }
}

.md-types {
  display: flex;
  flex-direction: column;
  gap: 1px;
  border-right: 1px solid var(--bd-1);
  padding-right: var(--sp-3);
}

@media (max-width: 1100px) {
  .md-types {
    border-right: none;
    border-bottom: 1px solid var(--bd-1);
    padding-right: 0;
    padding-bottom: var(--sp-3);
  }
}

.md-list {
  min-width: 0;
}

/* Codes are long (KNOWLEDGE_CATEGORY_001) and monospaced; wrapping them mid-token
   made a two-line cell for every row. Kept on one line, with the full value in
   the tooltip in case a future code outgrows the column. */
.md-code {
  display: block;
  white-space: nowrap;
  overflow: hidden;
  text-overflow: ellipsis;
}

.md-readonly {
  margin-bottom: var(--sp-3);
  padding: var(--sp-2) var(--sp-3);
  border: 1px solid var(--c-warning-border);
  background: var(--c-warning-soft);
  border-radius: var(--r-2);
  color: #B45309;
}

.md-field {
  width: 100%;
}

.md-hint {
  margin: -8px 0 var(--sp-3) 96px;
}
</style>
