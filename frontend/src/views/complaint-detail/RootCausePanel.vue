<script setup lang="ts">
import { computed, onMounted, reactive, ref } from 'vue'
import { ElMessage, ElMessageBox } from 'element-plus'
import {
  rootCauseApi,
  ANALYSIS_TYPE,
  ORG_TYPES,
  ROOT_CAUSE_STATUSES,
  type AnalysisView,
  type RootCauseDetail,
  type RootCauseRequest,
  type RootCauseView
} from '@/api/rootCause'
import { errorMessage } from '@/api/http'
import RowAction from '@/components/RowAction.vue'
import { useMetaStore } from '@/stores/meta'
import WhyMindMap from './WhyMindMap.vue'
import FishboneEditor from './FishboneEditor.vue'

/**
 * D4: root-cause analysis (requirement 3.5).
 *
 * The list carries the entries; each one opens a drawer holding its two analysis
 * tools. Both tools save as new versions, so a save never destroys the previous
 * content, and an older version can be pulled back into the editor and re-saved.
 */
const props = defineProps<{ complaintId: string; canEdit: boolean }>()
const emit = defineEmits<{ (e: 'refresh'): void }>()

const meta = useMetaStore()

const items = ref<RootCauseView[]>([])
const loading = ref(false)

const dialogVisible = ref(false)
const saving = ref(false)
const editingId = ref<string | null>(null)
const form = reactive<RootCauseRequest>(emptyForm())

const transferVisible = ref(false)
const transferSaving = ref(false)
const transferTargetId = ref<string | null>(null)
const transferForm = reactive<{ transferredToId: string; responsibleOrgType?: string | null; responsibleOrgCode?: string | null; note?: string | null }>({
  transferredToId: '',
  responsibleOrgType: null,
  responsibleOrgCode: null,
  note: null
})

const analysisVisible = ref(false)
const analysisType = ref<string>(ANALYSIS_TYPE.WHY)
const detail = ref<RootCauseDetail | null>(null)
const analysisSaving = ref(false)
const versions = ref<AnalysisView[]>([])
/** Bumped to force the editor to remount when a different version is loaded. */
const editorKey = ref(0)
const editorModel = ref<string | null>(null)
const whyRef = ref<InstanceType<typeof WhyMindMap> | null>(null)
const fishboneRef = ref<InstanceType<typeof FishboneEditor> | null>(null)

function emptyForm(): RootCauseRequest {
  return {
    rootCauseDesc: '',
    rootCauseSummary: null,
    riskAssessment: null,
    responsibleOrgType: 'INTERNAL',
    responsibleOrgCode: null,
    statusCode: 'ROOTCAUSE_TODO'
  }
}

async function refresh() {
  loading.value = true
  try {
    items.value = await rootCauseApi.list(props.complaintId)
  } catch (e) {
    ElMessage.error('根因列表加载失败：' + errorMessage(e))
  } finally {
    loading.value = false
  }
}

onMounted(refresh)

const analysisLabel = computed(() => (analysisType.value === ANALYSIS_TYPE.WHY ? '3x5Why' : '鱼骨图'))

// ---------------------------------------------------------------- root causes

function openCreate() {
  editingId.value = null
  Object.assign(form, emptyForm())
  dialogVisible.value = true
}

function openEdit(row: RootCauseView) {
  editingId.value = row.rootCauseId
  Object.assign(form, {
    rootCauseDesc: row.rootCauseDesc,
    rootCauseSummary: row.rootCauseSummary,
    riskAssessment: row.riskAssessment,
    responsibleOrgType: row.responsibleOrgType ?? 'INTERNAL',
    responsibleOrgCode: row.responsibleOrgCode,
    statusCode: row.statusCode
  })
  dialogVisible.value = true
}

async function save() {
  saving.value = true
  try {
    if (editingId.value) {
      await rootCauseApi.update(editingId.value, { ...form })
      ElMessage.success('根因已更新')
    } else {
      const created = await rootCauseApi.create(props.complaintId, { ...form })
      ElMessage.success('已创建根因：' + created.rootCause.rootCauseId)
    }
    dialogVisible.value = false
    await refresh()
    emit('refresh')
  } catch (e) {
    ElMessage.error(errorMessage(e))
  } finally {
    saving.value = false
  }
}

async function remove(row: RootCauseView) {
  try {
    await ElMessageBox.confirm(
      `确定删除根因 ${row.rootCauseId}？其下的 3x5Why 与鱼骨图内容会一并删除。`,
      '删除根因',
      { type: 'warning' }
    )
  } catch {
    return
  }
  try {
    await rootCauseApi.remove(row.rootCauseId)
    ElMessage.success('已删除')
    await refresh()
  } catch (e) {
    ElMessage.error(errorMessage(e))
  }
}

// ------------------------------------------------------------------ transfer

function openTransfer(row: RootCauseView) {
  editingId.value = row.rootCauseId
  transferTargetId.value = row.rootCauseId
  Object.assign(transferForm, {
    transferredToId: row.transferredToId ?? '',
    responsibleOrgType: row.responsibleOrgType ?? 'EXTERNAL',
    responsibleOrgCode: row.responsibleOrgCode,
    note: null
  })
  transferVisible.value = true
}

async function submitTransfer() {
  if (!transferTargetId.value) return
  transferSaving.value = true
  try {
    await rootCauseApi.transfer(transferTargetId.value, {
      transferredToId: transferForm.transferredToId,
      responsibleOrgType: transferForm.responsibleOrgType,
      responsibleOrgCode: transferForm.responsibleOrgCode,
      note: transferForm.note
    })
    ElMessage.success('已转交')
    transferVisible.value = false
    await refresh()
  } catch (e) {
    ElMessage.error(errorMessage(e))
  } finally {
    transferSaving.value = false
  }
}

// ------------------------------------------------------------------ analysis

async function openAnalysis(row: RootCauseView, type: string) {
  analysisType.value = type
  try {
    detail.value = await rootCauseApi.detail(row.rootCauseId)
  } catch (e) {
    ElMessage.error('根因详情加载失败：' + errorMessage(e))
    return
  }
  const saved = type === ANALYSIS_TYPE.WHY ? detail.value.whyAnalysis : detail.value.fishbone
  editorModel.value = saved?.contentJson ?? null
  editorKey.value += 1
  await loadVersions()
  analysisVisible.value = true
}

async function loadVersions() {
  if (!detail.value) return
  try {
    versions.value = await rootCauseApi.versions(
      detail.value.rootCause.rootCauseId,
      analysisType.value
    )
  } catch {
    // A missing history must not stop the editor from opening.
    versions.value = []
  }
}

/** Pulls an older version into the editor; saving then makes it the newest one. */
function loadVersion(version: AnalysisView) {
  editorModel.value = version.contentJson
  editorKey.value += 1
  ElMessage.info(`已载入 v${version.versionNo}，保存后将成为新版本`)
}

async function saveAnalysis() {
  if (!detail.value) return
  const rootCauseId = detail.value.rootCause.rootCauseId
  const content =
    analysisType.value === ANALYSIS_TYPE.WHY
      ? whyRef.value?.getData()
      : fishboneRef.value?.getData()
  if (!content) {
    ElMessage.error('无法读取编辑内容')
    return
  }
  analysisSaving.value = true
  try {
    detail.value = await rootCauseApi.saveAnalysis(rootCauseId, analysisType.value, content)
    ElMessage.success(
      '已保存为 v' + (analysisType.value === ANALYSIS_TYPE.WHY
        ? detail.value.whyAnalysis?.versionNo
        : detail.value.fishbone?.versionNo)
    )
    await loadVersions()
    await refresh()
  } catch (e) {
    ElMessage.error(errorMessage(e))
  } finally {
    analysisSaving.value = false
  }
}

function orgTypeLabel(code?: string | null): string {
  return ORG_TYPES.find((o) => o.code === code)?.label ?? '—'
}
</script>

<template>
  <div>
    <div class="row-between mb-3">
      <span class="fs-12 t-3">
        一个投诉可有多条根因；每条根因可分别用 3x5Why 与鱼骨图分析，保存会生成新版本、不覆盖旧内容。
      </span>
      <el-button v-if="canEdit" type="primary" plain @click="openCreate">新增根因</el-button>
    </div>

    <el-table :data="items" v-loading="loading" size="small" empty-text="尚未创建根因">
      <el-table-column prop="rootCauseId" label="根因ID" width="140" />
      <el-table-column label="根因摘要" min-width="220" show-overflow-tooltip>
        <template #default="{ row }">{{ row.rootCauseSummary || row.rootCauseDesc }}</template>
      </el-table-column>
      <el-table-column label="归属" width="110">
        <template #default="{ row }">
          <el-tag size="small" :type="row.responsibleOrgType === 'EXTERNAL' ? 'warning' : 'info'">
            {{ orgTypeLabel(row.responsibleOrgType) }}
          </el-tag>
        </template>
      </el-table-column>
      <el-table-column label="状态" width="100">
        <template #default="{ row }">
          <el-tag size="small" :type="row.statusCode === 'ROOTCAUSE_DONE' ? 'success' : ''">
            {{ row.statusName || row.statusCode }}
          </el-tag>
        </template>
      </el-table-column>
      <el-table-column label="转交对象" width="110">
        <template #default="{ row }">{{ row.transferredToName || '—' }}</template>
      </el-table-column>
      <el-table-column label="分析工具" width="230">
        <template #default="{ row }">
          <el-button link type="primary" @click="openAnalysis(row, ANALYSIS_TYPE.WHY)">
            3x5Why{{ row.whyVersionCount ? ' (v' + row.whyVersionCount + ')' : '' }}
          </el-button>
          <el-button link type="primary" @click="openAnalysis(row, ANALYSIS_TYPE.FISHBONE)">
            鱼骨图{{ row.fishboneVersionCount ? ' (v' + row.fishboneVersionCount + ')' : '' }}
          </el-button>
        </template>
      </el-table-column>
      <el-table-column v-if="canEdit" label="操作" width="122" fixed="right">
        <template #default="{ row }">
          <span class="row-acts">
            <RowAction act="edit" icon="pencil" label="编辑" @click="openEdit(row)" />
            <RowAction act="transfer" icon="transfer" label="转交" @click="openTransfer(row)" />
            <RowAction act="delete" icon="trash" tone="danger" label="删除" @click="remove(row)" />
          </span>
        </template>
      </el-table-column>
    </el-table>

    <!-- Root cause dialog -->
    <el-dialog
      v-model="dialogVisible"
      :title="editingId ? '编辑根因 ' + editingId : '新增根因'"
      width="860px"
      destroy-on-close
    >
      <el-form :model="form" label-width="130px">
        <el-form-item label="根因描述" required>
          <el-input
            v-model="form.rootCauseDesc"
            type="textarea"
            :rows="4"
            resize="none"
            placeholder="完整描述根因，可在附件中心挂分析图片"
          />
        </el-form-item>
        <el-form-item label="根因摘要">
          <el-input v-model="form.rootCauseSummary" maxlength="500" show-word-limit placeholder="用于报表与知识检索的短描述" />
        </el-form-item>
        <el-form-item label="风险评估">
          <el-input v-model="form.riskAssessment" type="textarea" :rows="3" resize="none" />
        </el-form-item>
        <el-row :gutter="16">
          <el-col :span="8">
            <el-form-item label="根因归属">
              <el-radio-group v-model="form.responsibleOrgType">
                <el-radio-button v-for="o in ORG_TYPES" :key="o.code" :value="o.code">{{ o.label }}</el-radio-button>
              </el-radio-group>
            </el-form-item>
          </el-col>
          <el-col :span="8">
            <el-form-item label="责任组织">
              <el-select v-model="form.responsibleOrgCode" clearable placeholder="请选择">
                <el-option v-for="o in meta.responsibleOrgs" :key="o.code" :label="o.nameCn" :value="o.code" />
              </el-select>
            </el-form-item>
          </el-col>
          <el-col :span="8">
            <el-form-item label="状态">
              <el-select v-model="form.statusCode" clearable>
                <el-option v-for="s in ROOT_CAUSE_STATUSES" :key="s.code" :label="s.label" :value="s.code" />
              </el-select>
            </el-form-item>
          </el-col>
        </el-row>
      </el-form>
      <template #footer>
        <el-button @click="dialogVisible = false">取消</el-button>
        <el-button type="primary" :loading="saving" @click="save">保存</el-button>
      </template>
    </el-dialog>

    <!-- Transfer dialog -->
    <el-dialog v-model="transferVisible" title="转交根因组织" width="700px" destroy-on-close>
      <el-alert
        class="mb-3"
        type="info"
        :closable="false"
        show-icon
        title="当根因不在本组织（流程图的 Root cause within Nexperia? 分支）时，转交给对应组织处理，转交时间自动留痕。"
      />
      <el-form label-width="130px">
        <el-form-item label="转交对象" required>
          <el-select v-model="transferForm.transferredToId" filterable placeholder="请选择接收人">
            <el-option v-for="e in meta.employees" :key="e.id" :label="e.name" :value="e.id">
              <span>{{ e.name }}</span>
              <span class="option-sub">{{ e.jobTitle || e.id }}</span>
            </el-option>
          </el-select>
        </el-form-item>
        <el-row :gutter="16">
          <el-col :span="12">
            <el-form-item label="根因归属">
              <el-radio-group v-model="transferForm.responsibleOrgType">
                <el-radio-button v-for="o in ORG_TYPES" :key="o.code" :value="o.code">{{ o.label }}</el-radio-button>
              </el-radio-group>
            </el-form-item>
          </el-col>
          <el-col :span="12">
            <el-form-item label="责任组织">
              <el-select v-model="transferForm.responsibleOrgCode" clearable placeholder="请选择">
                <el-option v-for="o in meta.responsibleOrgs" :key="o.code" :label="o.nameCn" :value="o.code" />
              </el-select>
            </el-form-item>
          </el-col>
        </el-row>
        <el-form-item label="转交说明">
          <el-input v-model="transferForm.note" type="textarea" :rows="3" resize="none" />
        </el-form-item>
      </el-form>
      <template #footer>
        <el-button @click="transferVisible = false">取消</el-button>
        <el-button type="primary" :loading="transferSaving" @click="submitTransfer">确认转交</el-button>
      </template>
    </el-dialog>

    <!-- Analysis drawer: one root cause, one tool -->
    <el-drawer
      v-model="analysisVisible"
      size="92%"
      :title="(detail?.rootCause.rootCauseId || '') + ' · ' + analysisLabel"
    >
      <div class="row-between mb-2">
        <span class="fs-12 t-3">
          {{ analysisType === ANALYSIS_TYPE.WHY
            ? '根节点是失效现象；下一层是「为什么」，再下一层是「原因」，如此交替，可任意加深。'
            : '左侧录入分类与原因，右侧实时生成鱼骨图。' }}
        </span>
        <span class="row gap-2">
          <el-dropdown v-if="versions.length" trigger="click" @command="loadVersion">
            <el-button size="small">
              版本历史（{{ versions.length }}）<span class="t-3">v{{ versions[0]?.versionNo }}</span>
            </el-button>
            <template #dropdown>
              <el-dropdown-menu>
                <el-dropdown-item v-for="v in versions" :key="v.analysisId" :command="v">
                  v{{ v.versionNo }} · {{ v.createdByName || v.createdBy }} ·
                  {{ v.createdAt ? String(v.createdAt).replace('T', ' ').slice(0, 16) : '' }}（点此载入）
                </el-dropdown-item>
              </el-dropdown-menu>
            </template>
          </el-dropdown>
          <el-button v-if="canEdit" type="primary" :loading="analysisSaving" @click="saveAnalysis">
            保存为新版本
          </el-button>
        </span>
      </div>

      <WhyMindMap
        v-if="analysisType === ANALYSIS_TYPE.WHY"
        :key="editorKey"
        ref="whyRef"
        :model-value="editorModel"
        :root-topic="detail?.rootCause.rootCauseSummary || '失效现象'"
        :readonly="!canEdit"
      />
      <FishboneEditor
        v-else
        :key="editorKey"
        ref="fishboneRef"
        :model-value="editorModel"
        :default-effect="detail?.rootCause.rootCauseSummary || '失效现象'"
        :readonly="!canEdit"
      />
    </el-drawer>
  </div>
</template>

<style scoped>
.option-sub {
  float: right;
  margin-left: 16px;
  color: var(--t-4);
  font-size: var(--fs-12);
}
</style>
