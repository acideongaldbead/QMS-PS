<script setup lang="ts">
import { computed, onMounted, reactive, ref } from 'vue'
import { ElMessage, ElMessageBox } from 'element-plus'
import {
  containmentApi,
  CONTAINMENT_STATUSES,
  type ActionRequest,
  type ActionView,
  type ContainmentSummary
} from '@/api/containment'
import { errorMessage } from '@/api/http'
import RowAction from '@/components/RowAction.vue'
import { useMetaStore } from '@/stores/meta'

/**
 * D3 containment (requirement 3.4, PS-039 to PS-041).
 *
 * D3 opens with a decision: if containment is not needed the stage is skipped
 * outright, so the question is asked before any action can be registered.
 */
const props = defineProps<{ complaintId: string; canEdit: boolean }>()
const emit = defineEmits<{ (e: 'refresh'): void }>()

const meta = useMetaStore()

const summary = ref<ContainmentSummary | null>(null)
const loading = ref(false)

const decisionForm = reactive<{ required: boolean | null; note: string | null }>({
  required: null,
  note: null
})
const deciding = ref(false)
const changingDecision = ref(false)

const actionDialog = ref(false)
const actionSaving = ref(false)
const editingActionId = ref<string | null>(null)
const actionForm = reactive<ActionRequest>(emptyAction())

function emptyAction(): ActionRequest {
  return {
    nexSampleNumber: null,
    customerSampleNumber: null,
    plannedAction: '',
    ownerId: '',
    plannedCompletionDate: null,
    completedDate: null,
    statusCode: 'CONTAIN_TODO',
    result: null
  }
}

async function refresh() {
  loading.value = true
  try {
    summary.value = await containmentApi.summary(props.complaintId)
    if (summary.value.required === null) {
      decisionForm.required = null
      decisionForm.note = null
    }
  } catch (e) {
    ElMessage.error('遏制措施加载失败：' + errorMessage(e))
  } finally {
    loading.value = false
  }
}

onMounted(refresh)

const decided = computed(() => summary.value?.required !== null && summary.value?.required !== undefined)
const required = computed(() => summary.value?.required === true)
const canEditHere = computed(() => props.canEdit && !summary.value?.complaintClosed)

// ------------------------------------------------------------------ decision

async function submitDecision() {
  if (decisionForm.required === null) {
    ElMessage.warning('请先判断是否需要遏制措施')
    return
  }
  if (!decisionForm.required && !decisionForm.note?.trim()) {
    ElMessage.warning('判定为「不需要」时必须填写理由')
    return
  }
  deciding.value = true
  try {
    summary.value = await containmentApi.decide(props.complaintId, decisionForm.required, decisionForm.note)
    ElMessage.success(
      decisionForm.required ? '已判定为需要遏制措施，请登记具体措施' : '已判定为不需要遏制措施，流程进入 D4'
    )
    changingDecision.value = false
    emit('refresh')
  } catch (e) {
    ElMessage.error(errorMessage(e))
  } finally {
    deciding.value = false
  }
}

function startChangeDecision() {
  changingDecision.value = true
  decisionForm.required = summary.value?.required ?? null
  decisionForm.note = summary.value?.decisionNote ?? null
}

// ------------------------------------------------------------------ actions

function openCreate() {
  editingActionId.value = null
  Object.assign(actionForm, emptyAction())
  actionDialog.value = true
}

function openEdit(row: ActionView) {
  editingActionId.value = row.actionId
  Object.assign(actionForm, {
    nexSampleNumber: row.nexSampleNumber,
    customerSampleNumber: row.customerSampleNumber,
    plannedAction: row.plannedAction,
    ownerId: row.ownerId,
    plannedCompletionDate: row.plannedCompletionDate,
    completedDate: row.completedDate,
    statusCode: row.statusCode,
    result: row.result
  })
  actionDialog.value = true
}

async function saveAction() {
  actionSaving.value = true
  try {
    if (editingActionId.value) {
      summary.value = await containmentApi.updateAction(editingActionId.value, { ...actionForm })
      ElMessage.success('遏制措施已更新')
    } else {
      summary.value = await containmentApi.createAction(props.complaintId, { ...actionForm })
      ElMessage.success('已登记遏制措施')
    }
    actionDialog.value = false
    emit('refresh')
  } catch (e) {
    ElMessage.error(errorMessage(e))
  } finally {
    actionSaving.value = false
  }
}

async function removeAction(row: ActionView) {
  try {
    await ElMessageBox.confirm(`确定删除遏制措施 ${row.actionId}？`, '删除措施', { type: 'warning' })
  } catch {
    return
  }
  try {
    summary.value = await containmentApi.removeAction(row.actionId)
    ElMessage.success('已删除')
    emit('refresh')
  } catch (e) {
    ElMessage.error(errorMessage(e))
  }
}

function statusTagType(code: string): string {
  if (code === 'CONTAIN_DONE') return 'success'
  if (code === 'CONTAIN_CANCELLED') return 'info'
  if (code === 'CONTAIN_DOING') return 'warning'
  return ''
}
</script>

<template>
  <div v-loading="loading">
    <el-alert
      v-if="summary?.complaintClosed"
      class="mb-3"
      type="info"
      :closable="false"
      show-icon
      title="该投诉单已结案，遏制措施仅供查看。"
    />

    <!-- The PS-039 decision, asked before any action can exist -->
    <el-card v-if="!decided || changingDecision" shadow="never" class="mb-4">
      <template #header>
        <span class="fw-semi">是否需要遏制措施</span>
        <span class="fs-12 t-3" style="margin-left: 8px">
          判定为「不需要」时 D3 整个跳过，流程直接进入 D4
        </span>
      </template>

      <el-form label-width="130px">
        <el-form-item label="判断结论" required>
          <el-radio-group v-model="decisionForm.required">
            <el-radio-button :value="true">需要遏制</el-radio-button>
            <el-radio-button :value="false">不需要遏制</el-radio-button>
          </el-radio-group>
        </el-form-item>
        <el-form-item label="判断理由" :required="decisionForm.required === false">
          <el-input
            v-model="decisionForm.note"
            type="textarea"
            :rows="3"
            resize="none"
            :placeholder="decisionForm.required === false ? '必填：说明为什么不需要遏制' : '可填写判断依据'"
          />
        </el-form-item>
      </el-form>

      <el-alert
        v-if="decisionForm.required === false"
        type="warning"
        :closable="false"
        show-icon
        title="判定为「不需要」后不能登记遏制措施；如需登记可再把判断改回「需要」。"
      />

      <div class="mt-4 row-end">
        <el-button v-if="changingDecision" @click="changingDecision = false">取消</el-button>
        <el-button
          type="primary"
          :loading="deciding"
          :disabled="!canEditHere"
          @click="submitDecision"
        >
          {{ changingDecision ? '提交修改' : '提交判断' }}
        </el-button>
      </div>
    </el-card>

    <!-- The decision, once made -->
    <el-card v-else shadow="never" class="mb-4">
      <template #header>
        <div class="row-between">
          <span>
            <span class="fw-semi">遏制判断</span>
            <el-tag
              :type="required ? 'warning' : 'success'"
              size="small"
              style="margin-left: 8px"
            >
              {{ required ? '需要遏制措施' : '不需要遏制措施' }}
            </el-tag>
          </span>
          <el-button v-if="canEditHere" link type="primary" @click="startChangeDecision">修改判断</el-button>
        </div>
      </template>
      <p class="fs-13 t-2" style="margin: 0">
        {{ summary?.decisionNote || '（未填写判断理由）' }}
      </p>
    </el-card>

    <!-- Actions, only meaningful when containment is required -->
    <el-card v-if="required" shadow="never">
      <template #header>
        <div class="row-between">
          <span class="fw-semi">遏制措施（{{ summary?.actions.length ?? 0 }}）</span>
          <el-button v-if="canEditHere" type="primary" plain @click="openCreate">新增遏制措施</el-button>
        </div>
      </template>

      <el-table :data="summary?.actions ?? []" size="small" empty-text="尚未登记遏制措施">
        <el-table-column prop="actionId" label="措施ID" width="140" />
        <el-table-column label="NEX样品号" width="120">
          <template #default="{ row }">{{ row.nexSampleNumber || '—' }}</template>
        </el-table-column>
        <el-table-column label="客户样品号" width="130">
          <template #default="{ row }">{{ row.customerSampleNumber || '—' }}</template>
        </el-table-column>
        <el-table-column prop="plannedAction" label="计划措施" min-width="240" show-overflow-tooltip />
        <el-table-column label="责任人" width="100">
          <template #default="{ row }">{{ row.ownerName || row.ownerId }}</template>
        </el-table-column>
        <el-table-column label="状态" width="100">
          <template #default="{ row }">
            <el-tag size="small" :type="statusTagType(row.statusCode)">
              {{ row.statusName || row.statusCode }}
            </el-tag>
          </template>
        </el-table-column>
        <el-table-column label="计划完成日期" width="120">
          <template #default="{ row }">{{ row.plannedCompletionDate || '—' }}</template>
        </el-table-column>
        <el-table-column label="完成日期" width="150">
          <template #default="{ row }">
            <span :class="{ 't-danger': !!row.completionWarning }">{{ row.completedDate || '—' }}</span>
            <el-tooltip v-if="row.completionWarning" :content="row.completionWarning" placement="top">
              <span class="warn-mark">!</span>
            </el-tooltip>
          </template>
        </el-table-column>
        <el-table-column label="结果" min-width="200" show-overflow-tooltip>
          <template #default="{ row }">{{ row.result || '—' }}</template>
        </el-table-column>
        <el-table-column v-if="canEditHere" label="操作" width="120" fixed="right">
          <template #default="{ row }">
            <span class="row-acts">
              <RowAction act="edit" icon="pencil" label="编辑" @click="openEdit(row)" />
              <RowAction act="delete" icon="trash" tone="danger" label="删除" @click="removeAction(row)" />
            </span>
          </template>
        </el-table-column>
      </el-table>
    </el-card>

    <!-- Action dialog -->
    <el-dialog
      v-model="actionDialog"
      :title="editingActionId ? '编辑遏制措施 ' + editingActionId : '新增遏制措施'"
      width="880px"
      destroy-on-close
    >
      <el-form :model="actionForm" label-width="130px">
        <el-row :gutter="16">
          <el-col :span="12">
            <el-form-item label="NEX 样品号">
              <el-input v-model="actionForm.nexSampleNumber" placeholder="NEX sample number" />
            </el-form-item>
          </el-col>
          <el-col :span="12">
            <el-form-item label="客户样品号">
              <el-input v-model="actionForm.customerSampleNumber" placeholder="customer sample number" />
            </el-form-item>
          </el-col>
        </el-row>
        <el-form-item label="计划措施" required>
          <el-input
            v-model="actionForm.plannedAction"
            type="textarea"
            :rows="3"
            resize="none"
            placeholder="要执行的具体遏制动作"
          />
        </el-form-item>
        <el-row :gutter="16">
          <el-col :span="6">
            <el-form-item label="责任人" required>
              <el-select v-model="actionForm.ownerId" filterable placeholder="请选择">
                <el-option v-for="e in meta.employees" :key="e.id" :label="e.name" :value="e.id">
                  <span>{{ e.name }}</span>
                  <span class="option-sub">{{ e.jobTitle || e.id }}</span>
                </el-option>
              </el-select>
            </el-form-item>
          </el-col>
          <el-col :span="6">
            <el-form-item label="状态">
              <el-select v-model="actionForm.statusCode" clearable>
                <el-option v-for="s in CONTAINMENT_STATUSES" :key="s.code" :label="s.label" :value="s.code" />
              </el-select>
            </el-form-item>
          </el-col>
          <el-col :span="6">
            <el-form-item label="计划完成日期">
              <el-date-picker
                v-model="actionForm.plannedCompletionDate"
                type="date"
                value-format="YYYY-MM-DD"
                placeholder="计划何时完成"
              />
            </el-form-item>
          </el-col>
          <el-col :span="6">
            <el-form-item label="完成日期">
              <el-date-picker
                v-model="actionForm.completedDate"
                type="date"
                value-format="YYYY-MM-DD"
                placeholder="留空则完成时自动填写"
              />
            </el-form-item>
          </el-col>
        </el-row>
        <el-form-item label="实施结果">
          <el-input v-model="actionForm.result" type="textarea" :rows="3" resize="none" />
        </el-form-item>
      </el-form>
      <template #footer>
        <el-button @click="actionDialog = false">取消</el-button>
        <el-button type="primary" :loading="actionSaving" @click="saveAction">保存</el-button>
      </template>
    </el-dialog>
  </div>
</template>

<style scoped>
.row-end {
  display: flex;
  justify-content: flex-end;
  gap: var(--sp-2);
}
.option-sub {
  float: right;
  margin-left: 16px;
  color: var(--t-4);
  font-size: var(--fs-12);
}
/* Marks a completion date that falls before the planned one; the tooltip spells
   out the comparison. */
.warn-mark {
  display: inline-block;
  width: 14px;
  height: 14px;
  line-height: 14px;
  text-align: center;
  border-radius: var(--r-full);
  background: var(--c-danger);
  color: #fff;
  font-size: 11px;
  margin-left: 4px;
}
</style>
