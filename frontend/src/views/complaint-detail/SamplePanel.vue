<script setup lang="ts">
import { computed, ref } from 'vue'
import { ElMessage, ElMessageBox } from 'element-plus'
import { complaintApi, type SampleForm } from '@/api/complaints'
import { errorMessage } from '@/api/http'
import { useMetaStore } from '@/stores/meta'
import SampleFields from '@/components/SampleFields.vue'

/**
 * The complaint's samples. Registration can create them up front, but parts often
 * arrive later, so requirement 3.1.6 allows adding and correcting them here.
 */
const props = defineProps<{
  complaintId: string
  samples: { sampleId: string; value: SampleForm }[]
  canEdit: boolean
}>()

const emit = defineEmits<{ (e: 'refresh'): void }>()
const meta = useMetaStore()

const dialogVisible = ref(false)
const saving = ref(false)
const editingId = ref<string | null>(null)
const form = ref<SampleForm>(emptyForm())

function emptyForm(): SampleForm {
  return {
    customerSampleId: null,
    champId: null,
    sampleQuantity: null,
    uom: 'PCS',
    description: null,
    productMarking: null,
    applicationArea: null,
    rejectConfirmed: null,
    conclusion: null,
    failureTypeL1Code: null,
    failureTypeL2Code: null,
    failureTypeL3Code: null
  }
}

/** Resolves the three codes to their display names for the table. */
function failureTypeLabel(sample: SampleForm): string {
  const names: string[] = []
  const flat: Record<string, string> = {}
  const walk = (nodes: typeof meta.failureTypes) => {
    for (const node of nodes) {
      flat[node.code] = node.name
      if (node.children?.length) walk(node.children)
    }
  }
  walk(meta.failureTypes)
  for (const code of [sample.failureTypeL1Code, sample.failureTypeL2Code, sample.failureTypeL3Code]) {
    if (code && flat[code]) names.push(flat[code])
  }
  return names.length ? names[names.length - 1] : '—'
}

function openAdd() {
  editingId.value = null
  form.value = emptyForm()
  dialogVisible.value = true
}

function openEdit(sampleId: string, value: SampleForm) {
  editingId.value = sampleId
  form.value = JSON.parse(JSON.stringify(value))
  dialogVisible.value = true
}

async function save() {
  saving.value = true
  try {
    if (editingId.value) {
      await complaintApi.updateSample(props.complaintId, editingId.value, form.value)
      ElMessage.success('样品已更新')
    } else {
      const created = await complaintApi.addSample(props.complaintId, form.value)
      ElMessage.success('样品已登记：' + created.sampleId)
    }
    dialogVisible.value = false
    emit('refresh')
  } catch (e) {
    ElMessage.error(errorMessage(e))
  } finally {
    saving.value = false
  }
}

async function remove(sampleId: string) {
  try {
    await ElMessageBox.confirm(`确定删除样品 ${sampleId}？`, '删除样品', { type: 'warning' })
  } catch {
    return
  }
  try {
    await complaintApi.removeSample(props.complaintId, sampleId)
    ElMessage.success('已删除')
    emit('refresh')
  } catch (e) {
    ElMessage.error(errorMessage(e))
  }
}

const rows = computed(() => props.samples)
</script>

<template>
  <div>
    <div class="row-between mb-3">
      <span class="fs-12 t-3">样品到达后可在此补录；已被物流批次引用的样品不能删除。</span>
      <el-button v-if="canEdit" type="primary" plain @click="openAdd">新增样品</el-button>
    </div>

    <el-table :data="rows" size="small" empty-text="尚未登记样品">
      <el-table-column prop="sampleId" label="样品ID" width="140" />
      <el-table-column label="客户样品ID" width="140">
        <template #default="{ row }">{{ row.value.customerSampleId || '—' }}</template>
      </el-table-column>
      <el-table-column label="Champ ID" width="130">
        <template #default="{ row }">{{ row.value.champId || '—' }}</template>
      </el-table-column>
      <el-table-column label="数量" width="110">
        <template #default="{ row }">
          {{ row.value.sampleQuantity ?? '—' }} {{ row.value.uom || '' }}
        </template>
      </el-table-column>
      <el-table-column label="失效类型" min-width="220" show-overflow-tooltip>
        <template #default="{ row }">{{ failureTypeLabel(row.value) }}</template>
      </el-table-column>
      <el-table-column label="拒收确认" width="100">
        <template #default="{ row }">
          <span v-if="row.value.rejectConfirmed === true" class="t-danger">是</span>
          <span v-else-if="row.value.rejectConfirmed === false">否</span>
          <span v-else>—</span>
        </template>
      </el-table-column>
      <el-table-column label="描述" min-width="180" show-overflow-tooltip>
        <template #default="{ row }">{{ row.value.description || '—' }}</template>
      </el-table-column>
      <el-table-column v-if="canEdit" label="操作" width="120" fixed="right">
        <template #default="{ row }">
          <el-button link type="primary" @click="openEdit(row.sampleId, row.value)">编辑</el-button>
          <el-button link type="danger" @click="remove(row.sampleId)">删除</el-button>
        </template>
      </el-table-column>
    </el-table>

    <el-dialog
      v-model="dialogVisible"
      :title="editingId ? '编辑样品 ' + editingId : '新增样品'"
      width="960px"
      destroy-on-close
    >
      <el-form label-width="130px">
        <SampleFields :model="form" />
      </el-form>
      <template #footer>
        <el-button @click="dialogVisible = false">取消</el-button>
        <el-button type="primary" :loading="saving" @click="save">保存</el-button>
      </template>
    </el-dialog>
  </div>
</template>
