<script setup lang="ts">
import { computed, onMounted, reactive, ref } from 'vue'
import { useI18n } from 'vue-i18n'
import { ElMessage, ElMessageBox } from 'element-plus'
import type { FormInstance, FormRules } from 'element-plus'
import { errorMessage } from '@/api/http'
import {
  announcementApi,
  type AnnouncementManage,
  type AnnouncementSaveRequest
} from '@/api/announcements'
import { useAuthStore } from '@/stores/auth'
import QmsIcon from '@/components/QmsIcon.vue'
import RowAction from '@/components/RowAction.vue'
import RichTextEditor from '@/components/RichTextEditor.vue'

/**
 * The announcement management screen (requirement 3.0 / PS-003).
 *
 * Only the administrator holds {@code announcement:manage}; the route is gated on
 * the same permission, so this is defence in depth. The home page keeps its own
 * read-only list and only ever shows the 已发布 entries.
 */
const { t } = useI18n()
const auth = useAuthStore()

const canManage = computed(() => auth.can('announcement:manage'))

/** publish_status is free text carrying the baseline's three values. */
const DRAFT = '草稿'
const PUBLISHED = '已发布'
const RETIRED = '已下架'

const rows = ref<AnnouncementManage[]>([])
const loading = ref(false)
const statusFilter = ref('')

const dialogOpen = ref(false)
const editingId = ref<number | null>(null)
const saving = ref(false)
const formRef = ref<FormInstance>()
const form = reactive<{ title: string; content: string; publishedAt: string | null }>({
  title: '',
  content: '',
  publishedAt: null
})

const rules: FormRules = {
  title: [{ required: true, message: t('ann.titleRequired'), trigger: 'blur' }]
}

function statusLabel(status: string): string {
  if (status === PUBLISHED) return t('ann.statusPublished')
  if (status === RETIRED) return t('ann.statusRetired')
  if (status === DRAFT) return t('ann.statusDraft')
  return status
}

function statusBadgeClass(status: string): string {
  if (status === PUBLISHED) return 'badge badge-success'
  if (status === RETIRED) return 'badge badge-warning'
  return 'badge badge-neutral'
}

function formatDateTime(value?: string | null): string {
  return value ? value.replace('T', ' ').slice(0, 16) : '—'
}

async function load() {
  loading.value = true
  try {
    rows.value = await announcementApi.list(statusFilter.value || undefined)
  } catch (e) {
    ElMessage.error(t('ann.loadFailed') + errorMessage(e))
  } finally {
    loading.value = false
  }
}

function openNew() {
  editingId.value = null
  form.title = ''
  form.content = ''
  form.publishedAt = null
  dialogOpen.value = true
}

function openEdit(row: AnnouncementManage) {
  editingId.value = row.announcementId
  form.title = row.title
  form.content = row.content ?? ''
  // The picker works on a wall-clock string; the stored value carries an offset.
  form.publishedAt = row.publishedAt ? row.publishedAt.slice(0, 19) : null
  dialogOpen.value = true
}

/** A body of only empty paragraphs is not content; the server refuses it too. */
function isBlankBody(html: string): boolean {
  return html.replace(/<[^>]*>/g, '').replace(/&nbsp;/g, ' ').trim() === ''
}

async function save() {
  const valid = await formRef.value?.validate().catch(() => false)
  if (!valid) return
  if (isBlankBody(form.content)) {
    ElMessage.warning(t('ann.contentRequired'))
    return
  }
  const body: AnnouncementSaveRequest = {
    title: form.title.trim(),
    content: form.content,
    publishedAt: form.publishedAt || null
  }
  saving.value = true
  try {
    if (editingId.value == null) {
      await announcementApi.create(body)
    } else {
      await announcementApi.update(editingId.value, body)
    }
    ElMessage.success(t('ann.saved'))
    dialogOpen.value = false
    await load()
  } catch (e) {
    ElMessage.error(errorMessage(e))
  } finally {
    saving.value = false
  }
}

/** The dialog is destroyed on close; re-read so the table reflects any save. */
function onDialogClosed() {
  load()
}

async function confirmThen(message: string, title: string): Promise<boolean> {
  try {
    await ElMessageBox.confirm(message, title, {
      type: 'warning',
      confirmButtonText: t('common.confirm'),
      cancelButtonText: t('common.cancel')
    })
    return true
  } catch {
    return false
  }
}

async function publish(row: AnnouncementManage) {
  if (!(await confirmThen(t('ann.publishConfirm', { title: row.title }), t('ann.publish')))) return
  try {
    await announcementApi.publish(row.announcementId)
    ElMessage.success(t('ann.published'))
    await load()
  } catch (e) {
    ElMessage.error(errorMessage(e))
  }
}

async function retire(row: AnnouncementManage) {
  if (!(await confirmThen(t('ann.retireConfirm', { title: row.title }), t('ann.retire')))) return
  try {
    await announcementApi.retire(row.announcementId)
    ElMessage.success(t('ann.retired'))
    await load()
  } catch (e) {
    ElMessage.error(errorMessage(e))
  }
}

async function remove(row: AnnouncementManage) {
  if (!(await confirmThen(t('ann.deleteConfirm', { title: row.title }), t('ann.del')))) return
  try {
    await announcementApi.remove(row.announcementId)
    ElMessage.success(t('ann.deleted'))
    await load()
  } catch (e) {
    ElMessage.error(errorMessage(e))
  }
}

onMounted(load)
</script>

<template>
  <div v-loading="loading">
    <div class="page-head">
      <div class="page-title-row">
        <div>
          <h1 class="page-title">{{ t('page.announcement') }}</h1>
          <div class="page-sub">{{ t('ann.sub') }}</div>
        </div>
        <div v-if="canManage" class="page-actions">
          <el-button type="primary" data-ann-new @click="openNew">
            <QmsIcon name="plus" :size="14" />
            <span>{{ t('ann.newAnn') }}</span>
          </el-button>
        </div>
      </div>
    </div>

    <div class="card">
      <div class="card-head">
        <div>
          <div class="card-title">{{ t('ann.listTitle') }}</div>
          <div class="card-sub" data-ann-heading>{{ t('ann.total', { n: rows.length }) }}</div>
        </div>
        <div class="card-head-actions">
          <div data-ann-filters>
            <el-radio-group v-model="statusFilter" @change="load">
              <el-radio-button value="">{{ t('ann.filterAll') }}</el-radio-button>
              <el-radio-button :value="DRAFT">{{ t('ann.statusDraft') }}</el-radio-button>
              <el-radio-button :value="PUBLISHED">{{ t('ann.statusPublished') }}</el-radio-button>
              <el-radio-button :value="RETIRED">{{ t('ann.statusRetired') }}</el-radio-button>
            </el-radio-group>
          </div>
        </div>
      </div>

      <div class="card-body flush">
        <el-table :data="rows" row-key="announcementId" data-ann-table>
          <el-table-column :label="t('ann.colTitle')" min-width="180">
            <template #default="{ row }">
              <span class="t-1 fw-medium" data-ann-title>{{ row.title }}</span>
            </template>
          </el-table-column>

          <el-table-column :label="t('ann.colStatus')" width="92">
            <template #default="{ row }">
              <span :class="statusBadgeClass(row.publishStatus)" data-ann-status>
                {{ statusLabel(row.publishStatus) }}
              </span>
            </template>
          </el-table-column>

          <el-table-column :label="t('ann.colPublishedAt')" width="156">
            <template #default="{ row }">
              <span class="mono fs-12 t-2">{{ formatDateTime(row.publishedAt) }}</span>
            </template>
          </el-table-column>

          <el-table-column :label="t('ann.colPublisher')" width="112">
            <template #default="{ row }">{{ row.publishedByName || '—' }}</template>
          </el-table-column>

          <el-table-column :label="t('ann.colUpdatedAt')" width="156">
            <template #default="{ row }">
              <span class="mono fs-12 t-3">{{ formatDateTime(row.updatedAt) }}</span>
            </template>
          </el-table-column>

          <el-table-column :label="t('common.actions')" width="122">
            <template #default="{ row }">
              <span class="row-acts">
                <RowAction act="edit" icon="pencil" :label="t('ann.edit')" @click="openEdit(row)" />
                <RowAction
                  v-if="row.publishStatus !== PUBLISHED"
                  act="publish"
                  icon="upload"
                  :label="row.publishStatus === RETIRED ? t('ann.republish') : t('ann.publish')"
                  @click="publish(row)"
                />
                <RowAction
                  v-if="row.publishStatus === PUBLISHED"
                  act="retire"
                  icon="arrowRightFromLine"
                  tone="warning"
                  :label="t('ann.retire')"
                  @click="retire(row)"
                />
                <RowAction act="delete" icon="trash" tone="danger" :label="t('ann.del')" @click="remove(row)" />
              </span>
            </template>
          </el-table-column>

          <template #empty>
            <div class="empty">
              <div class="empty-art"><QmsIcon name="bell" :size="26" /></div>
              <div class="empty-title">{{ t('ann.emptyTitle') }}</div>
              <div class="empty-text">{{ t('ann.emptyText') }}</div>
            </div>
          </template>
        </el-table>
      </div>
    </div>

    <el-dialog
      v-model="dialogOpen"
      :title="editingId == null ? t('ann.newAnn') : t('ann.editAnn')"
      width="820px"
      destroy-on-close
      @closed="onDialogClosed"
    >
      <el-form ref="formRef" :model="form" :rules="rules" label-width="96px" label-position="left">
        <el-form-item :label="t('ann.colTitle')" prop="title">
          <div class="ann-field" data-ann-field-title>
            <el-input v-model="form.title" maxlength="255" show-word-limit />
          </div>
        </el-form-item>

        <el-form-item :label="t('ann.publishedAtLabel')">
          <el-date-picker
            v-model="form.publishedAt"
            type="datetime"
            value-format="YYYY-MM-DDTHH:mm:ss"
            :placeholder="t('ann.publishedAtHint')"
            style="width: 100%"
          />
        </el-form-item>

        <el-form-item :label="t('ann.contentLabel')" required>
          <div class="ann-editor-wrap" data-ann-field-content>
            <RichTextEditor v-model="form.content" />
          </div>
        </el-form-item>
      </el-form>

      <template #footer>
        <el-button @click="dialogOpen = false">{{ t('common.cancel') }}</el-button>
        <el-button type="primary" :loading="saving" data-ann-save @click="save">
          {{ t('common.save') }}
        </el-button>
      </template>
    </el-dialog>
  </div>
</template>

<style scoped>
.ann-field,
.ann-editor-wrap {
  width: 100%;
}

/* The radio group is the status filter; keep it on one line beside the title. */
[data-ann-filters] :deep(.el-radio-group) {
  flex-wrap: nowrap;
}
</style>
