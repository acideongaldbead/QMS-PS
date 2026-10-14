<script setup lang="ts">
import { onMounted, reactive, ref } from 'vue'
import { ElMessage, ElMessageBox } from 'element-plus'
import type { FormInstance, FormRules } from 'element-plus'
import {
  actionsApi,
  CORRECTIVE_STATUSES,
  type CorrectiveActionRequest,
  type CorrectiveActionView
} from '@/api/actions'
import { rootCauseApi, type RootCauseView } from '@/api/rootCause'
import { errorMessage } from '@/api/http'
import { useMetaStore } from '@/stores/meta'

/**
 * D5: the permanent corrective actions (requirement 3.6).
 *
 * Every action must come from a root cause of the same complaint, so the dialog
 * offers that complaint's root causes rather than a free list -- the server
 * refuses a root cause from elsewhere, and the form should not let it be picked.
 */
const props = defineProps<{ complaintId: string; canEdit: boolean }>()
const emit = defineEmits<{ (e: 'refresh'): void }>()

const meta = useMetaStore()

const items = ref<CorrectiveActionView[]>([])
const rootCauses = ref<RootCauseView[]>([])
const loading = ref(false)

const dialogVisible = ref(false)
const saving = ref(false)
const editingId = ref<string | null>(null)
const formRef = ref<FormInstance>()
const form = reactive<CorrectiveActionRequest>(emptyForm())

const rules: FormRules = {
  rootCauseId: [{ required: true, message: '请选择关联根因', trigger: 'change' }],
  plannedActionDesc: [{ required: true, message: '请填写计划措施', trigger: 'blur' }],
  ownerId: [{ required: true, message: '请选择责任人', trigger: 'change' }],
  targetDate: [{ required: true, message: '请选择目标日期', trigger: 'change' }]
}

function emptyForm(): CorrectiveActionRequest {
  return {
    rootCauseId: '',
    nexSampleNumber: null,
    customerSampleId: null,
    plannedActionDesc: '',
    ownerId: '',
    targetDate: '',
    statusCode: 'CORR_TODO'
  }
}

async function refresh() {
  loading.value = true
  try {
    const [actions, roots] = await Promise.all([
      actionsApi.listActions(props.complaintId),
      rootCauseApi.list(props.complaintId)
    ])
    items.value = actions
    rootCauses.value = roots
  } catch (e) {
    ElMessage.error('纠正措施加载失败：' + errorMessage(e))
  } finally {
    loading.value = false
  }
}

onMounted(refresh)

function openCreate() {
  editingId.value = null
  Object.assign(form, emptyForm())
  // Pre-select when there is exactly one root cause; otherwise make the user choose.
  if (rootCauses.value.length === 1) {
    form.rootCauseId = rootCauses.value[0].rootCauseId
  }
  dialogVisible.value = true
}

function openEdit(row: CorrectiveActionView) {
  editingId.value = row.correctiveActionId
  Object.assign(form, {
    rootCauseId: row.rootCauseId,
    nexSampleNumber: row.nexSampleNumber,
    customerSampleId: row.customerSampleId,
    plannedActionDesc: row.plannedActionDesc,
    ownerId: row.ownerId,
    targetDate: row.targetDate,
    statusCode: row.statusCode
  })
  dialogVisible.value = true
}

async function save() {
  if (!formRef.value) return
  try {
    await formRef.value.validate()
  } catch {
    return
  }
  saving.value = true
  try {
    if (editingId.value) {
      await actionsApi.updateAction(editingId.value, { ...form })
      ElMessage.success('纠正措施已更新')
    } else {
      const created = await actionsApi.createAction(props.complaintId, { ...form })
      ElMessage.success('已创建纠正措施：' + created.action.correctiveActionId)
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

async function remove(row: CorrectiveActionView) {
  try {
    await ElMessageBox.confirm(
      `确定删除纠正措施 ${row.correctiveActionId}？其 D6 验证记录会一并删除。`,
      '删除纠正措施',
      { type: 'warning' }
    )
  } catch {
    return
  }
  try {
    await actionsApi.removeAction(row.correctiveActionId)
    ElMessage.success('已删除')
    await refresh()
    emit('refresh')
  } catch (e) {
    ElMessage.error(errorMessage(e))
  }
}

function statusTagType(code: string): string {
  if (code === 'CORR_VERIFIED') return 'success'
  if (code === 'CORR_FAILED') return 'danger'
  if (code === 'CORR_DONE') return 'warning'
  return ''
}
</script>

<template>
  <div>
    <div class="row-between mb-3">
      <span class="fs-12 t-3">
        纠正措施基于 D4 的根因制定；实施与有效性验证在 D6 页签录入。
      </span>
      <el-button v-if="canEdit" type="primary" plain @click="openCreate">新增纠正措施</el-button>
    </div>

    <el-table :data="items" v-loading="loading" size="small" empty-text="尚未制定纠正措施">
      <el-table-column prop="correctiveActionId" label="措施ID" width="140" />
      <el-table-column label="根因" min-width="180" show-overflow-tooltip>
        <template #default="{ row }">{{ row.rootCauseSummary || row.rootCauseId }}</template>
      </el-table-column>
      <el-table-column prop="plannedActionDesc" label="计划措施" min-width="240" show-overflow-tooltip />
      <el-table-column label="责任人" width="100">
        <template #default="{ row }">{{ row.ownerName || row.ownerId }}</template>
      </el-table-column>
      <el-table-column prop="targetDate" label="目标日期" width="120" />
      <el-table-column label="状态" width="110">
        <template #default="{ row }">
          <el-tag size="small" :type="statusTagType(row.statusCode)">
            {{ row.statusName || row.statusCode }}
          </el-tag>
        </template>
      </el-table-column>
      <el-table-column v-if="canEdit" label="操作" width="120" fixed="right">
        <template #default="{ row }">
          <el-button link type="primary" @click="openEdit(row)">编辑</el-button>
          <el-button link type="danger" @click="remove(row)">删除</el-button>
        </template>
      </el-table-column>
    </el-table>

    <el-dialog
      v-model="dialogVisible"
      :title="editingId ? '编辑纠正措施 ' + editingId : '新增纠正措施'"
      width="880px"
      destroy-on-close
    >
      <el-form ref="formRef" :model="form" :rules="rules" label-width="130px">
        <el-form-item label="关联根因" prop="rootCauseId" required>
          <el-select v-model="form.rootCauseId" placeholder="请选择本投诉的根因">
            <el-option
              v-for="rc in rootCauses"
              :key="rc.rootCauseId"
              :label="(rc.rootCauseSummary || rc.rootCauseDesc) + '（' + rc.rootCauseId + '）'"
              :value="rc.rootCauseId"
            />
          </el-select>
        </el-form-item>
        <el-form-item label="计划措施" prop="plannedActionDesc" required>
          <el-input
            v-model="form.plannedActionDesc"
            type="textarea"
            :rows="3"
            resize="none"
            placeholder="要实施的永久纠正措施"
          />
        </el-form-item>
        <el-row :gutter="16">
          <el-col :span="12">
            <el-form-item label="责任人" prop="ownerId" required>
              <el-select v-model="form.ownerId" filterable placeholder="请选择">
                <el-option v-for="e in meta.employees" :key="e.id" :label="e.name" :value="e.id">
                  <span>{{ e.name }}</span>
                  <span class="option-sub">{{ e.jobTitle || e.id }}</span>
                </el-option>
              </el-select>
            </el-form-item>
          </el-col>
          <el-col :span="12">
            <el-form-item label="目标日期" prop="targetDate" required>
              <el-date-picker
                v-model="form.targetDate"
                type="date"
                value-format="YYYY-MM-DD"
                style="width: 100%"
              />
            </el-form-item>
          </el-col>
        </el-row>
        <el-row :gutter="16">
          <el-col :span="12">
            <el-form-item label="NEX 样品号">
              <el-input v-model="form.nexSampleNumber" />
            </el-form-item>
          </el-col>
          <el-col :span="12">
            <el-form-item label="客户样品ID">
              <el-input v-model="form.customerSampleId" />
            </el-form-item>
          </el-col>
        </el-row>
        <el-form-item label="状态">
          <el-select v-model="form.statusCode" clearable>
            <el-option v-for="s in CORRECTIVE_STATUSES" :key="s.code" :label="s.label" :value="s.code" />
          </el-select>
        </el-form-item>
      </el-form>
      <template #footer>
        <el-button @click="dialogVisible = false">取消</el-button>
        <el-button type="primary" :loading="saving" @click="save">保存</el-button>
      </template>
    </el-dialog>
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
