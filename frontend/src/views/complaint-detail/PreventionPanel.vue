<script setup lang="ts">
import { onMounted, reactive, ref } from 'vue'
import { ElMessage, ElMessageBox } from 'element-plus'
import type { FormInstance, FormRules } from 'element-plus'
import {
  actionsApi,
  PREVENTION_STATUSES,
  type PreventionRequest,
  type PreventionView
} from '@/api/actions'
import { errorMessage } from '@/api/http'
import { useMetaStore } from '@/stores/meta'

/**
 * D7: preventing recurrence by tracking the documents that must be updated so the
 * failure cannot come back -- FMEA, Control Plan, OCAP, SOP, Update on Flow
 * (requirement 3.8).
 *
 * Every file being complete is the precondition for entering D8, so the panel
 * spells that out and the report stage checks it. The FMEA-system linkage is a
 * phase-two feature and is not offered here.
 */
const props = defineProps<{ complaintId: string; canEdit: boolean }>()
const emit = defineEmits<{ (e: 'refresh'): void }>()

const meta = useMetaStore()

const items = ref<PreventionView[]>([])
const loading = ref(false)

const dialogVisible = ref(false)
const saving = ref(false)
const editingId = ref<number | null>(null)
const formRef = ref<FormInstance>()
const form = reactive<PreventionRequest>(emptyForm())

const rules: FormRules = {
  fileTypeCode: [{ required: true, message: '请选择文件类型', trigger: 'change' }]
}

function emptyForm(): PreventionRequest {
  return {
    fileTypeCode: '',
    nexSampleNumber: null,
    customerSampleId: null,
    controlProgram: null,
    referenceNumber: null,
    statusCode: 'PREV_TODO'
  }
}

async function refresh() {
  loading.value = true
  try {
    items.value = await actionsApi.listPrevention(props.complaintId)
  } catch (e) {
    ElMessage.error('预防文件加载失败：' + errorMessage(e))
  } finally {
    loading.value = false
  }
}

onMounted(refresh)

function openCreate() {
  editingId.value = null
  Object.assign(form, emptyForm())
  dialogVisible.value = true
}

function openEdit(row: PreventionView) {
  editingId.value = row.updateId
  Object.assign(form, {
    fileTypeCode: row.fileTypeCode,
    nexSampleNumber: row.nexSampleNumber,
    customerSampleId: row.customerSampleId,
    controlProgram: row.controlProgram,
    referenceNumber: row.referenceNumber,
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
    if (editingId.value !== null) {
      await actionsApi.updatePrevention(editingId.value, { ...form })
      ElMessage.success('预防文件已更新')
    } else {
      await actionsApi.createPrevention(props.complaintId, { ...form })
      ElMessage.success('已登记预防文件')
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

async function remove(row: PreventionView) {
  try {
    await ElMessageBox.confirm(
      `确定删除这条预防文件记录（${row.fileTypeName || row.fileTypeCode}）？`,
      '删除预防文件',
      { type: 'warning' }
    )
  } catch {
    return
  }
  try {
    await actionsApi.removePrevention(row.updateId)
    ElMessage.success('已删除')
    await refresh()
    emit('refresh')
  } catch (e) {
    ElMessage.error(errorMessage(e))
  }
}

function statusTagType(code: string): string {
  if (code === 'PREV_DONE') return 'success'
  if (code === 'PREV_DOING') return 'warning'
  return 'info'
}

function formatTime(value?: string | null): string {
  return value ? String(value).replace('T', ' ').slice(0, 16) : '—'
}
</script>

<template>
  <div>
    <div class="row-between mb-3">
      <span class="fs-12 t-3">
        登记需更新的文件并跟踪其完成状态；所有文件完成后才能进入 D8。
      </span>
      <el-button v-if="canEdit" type="primary" plain @click="openCreate">登记文件更新</el-button>
    </div>

    <el-table :data="items" v-loading="loading" size="small" empty-text="尚未登记预防文件">
      <el-table-column label="文件类型" width="150">
        <template #default="{ row }">{{ row.fileTypeName || row.fileTypeCode }}</template>
      </el-table-column>
      <el-table-column label="NEX 样品号" width="130">
        <template #default="{ row }">{{ row.nexSampleNumber || '—' }}</template>
      </el-table-column>
      <el-table-column label="客户样品ID" width="130">
        <template #default="{ row }">{{ row.customerSampleId || '—' }}</template>
      </el-table-column>
      <el-table-column label="Control program" min-width="160" show-overflow-tooltip>
        <template #default="{ row }">{{ row.controlProgram || '—' }}</template>
      </el-table-column>
      <el-table-column label="参考编号" min-width="140" show-overflow-tooltip>
        <template #default="{ row }">{{ row.referenceNumber || '—' }}</template>
      </el-table-column>
      <el-table-column label="状态" width="100">
        <template #default="{ row }">
          <el-tag size="small" :type="statusTagType(row.statusCode)">
            {{ row.statusName || row.statusCode }}
          </el-tag>
        </template>
      </el-table-column>
      <el-table-column label="登记人" width="100">
        <template #default="{ row }">{{ row.createdByName || '—' }}</template>
      </el-table-column>
      <el-table-column label="登记时间" width="150">
        <template #default="{ row }">{{ formatTime(row.createdAt) }}</template>
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
      :title="editingId !== null ? '编辑预防文件' : '登记预防文件'"
      width="760px"
      destroy-on-close
    >
      <el-form ref="formRef" :model="form" :rules="rules" label-width="130px">
        <el-form-item label="文件类型" prop="fileTypeCode" required>
          <el-select v-model="form.fileTypeCode" placeholder="请选择需更新的文件">
            <el-option
              v-for="f in meta.fileTypes"
              :key="f.code"
              :label="f.nameCn"
              :value="f.code"
            />
          </el-select>
        </el-form-item>
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
        <el-row :gutter="16">
          <el-col :span="12">
            <el-form-item label="Control program">
              <el-input v-model="form.controlProgram" />
            </el-form-item>
          </el-col>
          <el-col :span="12">
            <el-form-item label="参考编号">
              <el-input v-model="form.referenceNumber" />
            </el-form-item>
          </el-col>
        </el-row>
        <el-form-item label="状态">
          <el-select v-model="form.statusCode" clearable>
            <el-option v-for="s in PREVENTION_STATUSES" :key="s.code" :label="s.label" :value="s.code" />
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
