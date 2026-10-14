<script setup lang="ts">
import { computed, onMounted, reactive, ref } from 'vue'
import { ElMessage, ElMessageBox } from 'element-plus'
import {
  logisticsApi,
  SHIPMENT_STATUSES,
  type ShipmentDetail,
  type ShipmentRequest,
  type ShipmentView
} from '@/api/logistics'
import { errorMessage } from '@/api/http'
import { useMetaStore } from '@/stores/meta'

/**
 * Sample logistics (requirement 3.2). A complaint can have several batches, and
 * a sample can travel in more than one, so samples are moved between the
 * complaint's pool and a batch rather than "owned" by it.
 */
const props = defineProps<{ complaintId: string; canEdit: boolean }>()
const meta = useMetaStore()

const items = ref<ShipmentView[]>([])
const loading = ref(false)

const formDialog = ref(false)
const saving = ref(false)
const editingId = ref<string | null>(null)
const form = reactive<ShipmentRequest>(emptyForm())

const detailDrawer = ref(false)
const currentDetail = ref<ShipmentDetail | null>(null)
const detailLoading = ref(false)

const addDialog = ref(false)
const addSaving = ref(false)
const selectedSampleIds = ref<string[]>([])
const batchAttrs = reactive({
  dateCode: null as string | null,
  dbId: null as string | null,
  assemblyCenter: null as string | null,
  testCenter: null as string | null,
  numOfDies: null as number | null,
  qty: null as number | null,
  uom: 'PCS'
})

function emptyForm(): ShipmentRequest {
  return {
    senderId: '',
    receiverId: '',
    shipmentNo: null,
    shipmentStatus: 'SHIPMENT_PREPARING',
    quantityPartsShipped: null,
    application: 'Yes',
    startDate: null,
    carrierName: '',
    carrierTrackingNumber: null,
    targetDate: null,
    closeDate: null,
    comments: null
  }
}

async function refresh() {
  loading.value = true
  try {
    items.value = await logisticsApi.listShipments(props.complaintId)
  } catch (e) {
    ElMessage.error('物流批次加载失败：' + errorMessage(e))
  } finally {
    loading.value = false
  }
}

onMounted(refresh)

/** Samples of this complaint that are not yet in the batch being viewed. */
const addableSamples = computed(
  () => currentDetail.value?.availableSamples.filter((s) => !s.inThisShipment) ?? []
)

function openCreate() {
  editingId.value = null
  Object.assign(form, emptyForm())
  formDialog.value = true
}

function openEdit(row: ShipmentView) {
  editingId.value = row.shipmentId
  Object.assign(form, {
    senderId: row.senderId,
    receiverId: row.receiverId,
    shipmentNo: row.shipmentNo,
    shipmentStatus: row.shipmentStatus,
    quantityPartsShipped: row.quantityPartsShipped,
    application: row.application,
    startDate: row.startDate,
    carrierName: row.carrierName,
    carrierTrackingNumber: row.carrierTrackingNumber,
    targetDate: row.targetDate,
    closeDate: row.closeDate,
    comments: row.comments
  })
  formDialog.value = true
}

async function save() {
  saving.value = true
  try {
    if (editingId.value) {
      currentDetail.value = await logisticsApi.updateShipment(editingId.value, toPayload())
      ElMessage.success('批次已更新')
    } else {
      const created = await logisticsApi.createShipment(props.complaintId, toPayload())
      currentDetail.value = created
      ElMessage.success('已创建物流批次：' + created.shipment.shipmentId)
    }
    formDialog.value = false
    await refresh()
  } catch (e) {
    ElMessage.error(errorMessage(e))
  } finally {
    saving.value = false
  }
}

function toPayload(): ShipmentRequest {
  return { ...form }
}

async function openDetail(row: ShipmentView) {
  detailDrawer.value = true
  await loadDetail(row.shipmentId)
}

async function loadDetail(shipmentId: string) {
  detailLoading.value = true
  try {
    currentDetail.value = await logisticsApi.shipmentDetail(shipmentId)
  } catch (e) {
    ElMessage.error('批次详情加载失败：' + errorMessage(e))
  } finally {
    detailLoading.value = false
  }
}

async function removeShipment(row: ShipmentView) {
  try {
    await ElMessageBox.confirm(`确定删除物流批次 ${row.shipmentId}？`, '删除批次', { type: 'warning' })
  } catch {
    return
  }
  try {
    await logisticsApi.removeShipment(row.shipmentId)
    ElMessage.success('已删除')
    await refresh()
  } catch (e) {
    ElMessage.error(errorMessage(e))
  }
}

function openAddSamples() {
  selectedSampleIds.value = []
  Object.assign(batchAttrs, {
    dateCode: null,
    dbId: null,
    assemblyCenter: null,
    testCenter: null,
    numOfDies: null,
    qty: null,
    uom: 'PCS'
  })
  addDialog.value = true
}

/**
 * The batch attributes are entered once and applied to every selected sample:
 * parts in one shipment normally share a date code and the same centres, and
 * asking for them per row would be busywork.
 */
async function confirmAddSamples() {
  const shipmentId = currentDetail.value?.shipment.shipmentId
  if (!shipmentId) return
  if (selectedSampleIds.value.length === 0) {
    ElMessage.warning('请先选择要加入的样品')
    return
  }
  addSaving.value = true
  try {
    currentDetail.value = await logisticsApi.addSamples(
      shipmentId,
      selectedSampleIds.value.map((sampleId) => ({
        sampleId,
        dateCode: batchAttrs.dateCode,
        dbId: batchAttrs.dbId,
        assemblyCenter: batchAttrs.assemblyCenter,
        testCenter: batchAttrs.testCenter,
        numOfDies: batchAttrs.numOfDies,
        qty: batchAttrs.qty,
        uom: batchAttrs.uom
      }))
    )
    ElMessage.success(`已加入 ${selectedSampleIds.value.length} 个样品`)
    addDialog.value = false
    await refresh()
  } catch (e) {
    ElMessage.error(errorMessage(e))
  } finally {
    addSaving.value = false
  }
}

async function removeSampleFromBatch(sampleId: string) {
  const shipmentId = currentDetail.value?.shipment.shipmentId
  if (!shipmentId) return
  try {
    currentDetail.value = await logisticsApi.removeSample(shipmentId, sampleId)
    ElMessage.success('已从批次移除')
    await refresh()
  } catch (e) {
    ElMessage.error(errorMessage(e))
  }
}
</script>

<template>
  <div>
    <div class="row-between mb-3">
      <span class="fs-12 t-3">
        一个投诉可分批寄送；同一个样品可出现在多个批次中。批次详情里可把样品移入或移出。
      </span>
      <el-button v-if="canEdit" type="primary" plain @click="openCreate">新增物流批次</el-button>
    </div>

    <el-table :data="items" v-loading="loading" size="small" empty-text="尚未登记物流批次">
      <el-table-column prop="shipmentId" label="批次ID" width="140" />
      <el-table-column prop="shipmentNo" label="物流单号" width="130">
        <template #default="{ row }">{{ row.shipmentNo || '—' }}</template>
      </el-table-column>
      <el-table-column label="状态" width="110">
        <template #default="{ row }">
          <el-tag size="small" :type="row.closeDate ? 'success' : 'info'">
            {{ row.shipmentStatusName || row.shipmentStatus }}
          </el-tag>
        </template>
      </el-table-column>
      <el-table-column prop="carrierName" label="承运商" width="130" />
      <el-table-column prop="quantityPartsShipped" label="寄送数量" width="100" />
      <el-table-column label="样品数" width="90">
        <template #default="{ row }">{{ row.sampleCount }}</template>
      </el-table-column>
      <el-table-column label="收件人" width="100">
        <template #default="{ row }">{{ row.receiverName || row.receiverId }}</template>
      </el-table-column>
      <el-table-column label="目标日期" width="120">
        <template #default="{ row }">
          <span :class="{ 't-danger': row.overdueDays > 0 }">{{ row.targetDate || '—' }}</span>
        </template>
      </el-table-column>
      <el-table-column label="操作" width="200" fixed="right">
        <template #default="{ row }">
          <el-button link type="primary" @click="openDetail(row)">详情</el-button>
          <el-button v-if="canEdit" link type="primary" @click="openEdit(row)">编辑</el-button>
          <el-button v-if="canEdit" link type="danger" @click="removeShipment(row)">删除</el-button>
        </template>
      </el-table-column>
    </el-table>

    <!-- Create / edit a batch -->
    <el-dialog
      v-model="formDialog"
      :title="editingId ? '编辑物流批次 ' + editingId : '新增物流批次'"
      width="820px"
      destroy-on-close
    >
      <el-form :model="form" label-width="130px">
        <el-row :gutter="16">
          <el-col :span="12">
            <el-form-item label="寄件人" required>
              <el-select v-model="form.senderId" filterable placeholder="请选择">
                <el-option v-for="e in meta.employees" :key="e.id" :label="e.name" :value="e.id" />
              </el-select>
            </el-form-item>
          </el-col>
          <el-col :span="12">
            <el-form-item label="收件人" required>
              <el-select v-model="form.receiverId" filterable placeholder="请选择">
                <el-option v-for="e in meta.employees" :key="e.id" :label="e.name" :value="e.id" />
              </el-select>
            </el-form-item>
          </el-col>
        </el-row>
        <el-row :gutter="16">
          <el-col :span="12">
            <el-form-item label="承运商" required>
              <el-input v-model="form.carrierName" placeholder="Carrier Name" />
            </el-form-item>
          </el-col>
          <el-col :span="12">
            <el-form-item label="跟踪号">
              <el-input v-model="form.carrierTrackingNumber" placeholder="Carrier Tracking Number" />
            </el-form-item>
          </el-col>
        </el-row>
        <el-row :gutter="16">
          <el-col :span="12">
            <el-form-item label="物流单号">
              <el-input v-model="form.shipmentNo" placeholder="Shipment ID" />
            </el-form-item>
          </el-col>
          <el-col :span="12">
            <el-form-item label="寄送数量" required>
              <el-input-number v-model="form.quantityPartsShipped" :min="0" :controls="false" />
            </el-form-item>
          </el-col>
        </el-row>
        <el-row :gutter="16">
          <el-col :span="12">
            <el-form-item label="物流状态">
              <el-select v-model="form.shipmentStatus" clearable>
                <el-option v-for="s in SHIPMENT_STATUSES" :key="s.code" :label="s.label" :value="s.code" />
              </el-select>
            </el-form-item>
          </el-col>
          <el-col :span="12">
            <el-form-item label="应用">
              <el-radio-group v-model="form.application">
                <el-radio-button value="Yes">Yes</el-radio-button>
                <el-radio-button value="No">No</el-radio-button>
              </el-radio-group>
            </el-form-item>
          </el-col>
        </el-row>
        <el-row :gutter="16">
          <el-col :span="8">
            <el-form-item label="开始日期">
              <el-date-picker v-model="form.startDate" type="date" value-format="YYYY-MM-DD" />
            </el-form-item>
          </el-col>
          <el-col :span="8">
            <el-form-item label="目标日期">
              <el-date-picker v-model="form.targetDate" type="date" value-format="YYYY-MM-DD" />
            </el-form-item>
          </el-col>
          <el-col :span="8">
            <el-form-item label="关闭日期">
              <el-date-picker v-model="form.closeDate" type="date" value-format="YYYY-MM-DD" />
            </el-form-item>
          </el-col>
        </el-row>
        <el-form-item label="备注">
          <el-input v-model="form.comments" type="textarea" :rows="2" />
        </el-form-item>
      </el-form>
      <template #footer>
        <el-button @click="formDialog = false">取消</el-button>
        <el-button type="primary" :loading="saving" @click="save">保存</el-button>
      </template>
    </el-dialog>

    <!-- Batch detail: what it carries, and what could be added -->
    <el-drawer v-model="detailDrawer" size="60%" :title="'物流批次 ' + (currentDetail?.shipment.shipmentId || '')">
      <div v-loading="detailLoading">
        <template v-if="currentDetail">
          <el-descriptions :column="2" border size="small">
            <el-descriptions-item label="状态">{{ currentDetail.shipment.shipmentStatusName }}</el-descriptions-item>
            <el-descriptions-item label="承运商">
              {{ currentDetail.shipment.carrierName }}
              <span class="t-3">{{ currentDetail.shipment.carrierTrackingNumber }}</span>
            </el-descriptions-item>
            <el-descriptions-item label="寄件人">{{ currentDetail.shipment.senderName }}</el-descriptions-item>
            <el-descriptions-item label="收件人">{{ currentDetail.shipment.receiverName }}</el-descriptions-item>
            <el-descriptions-item label="开始日期">{{ currentDetail.shipment.startDate || '—' }}</el-descriptions-item>
            <el-descriptions-item label="目标日期">{{ currentDetail.shipment.targetDate || '—' }}</el-descriptions-item>
            <el-descriptions-item label="关闭日期">{{ currentDetail.shipment.closeDate || '—' }}</el-descriptions-item>
            <el-descriptions-item label="寄送数量">{{ currentDetail.shipment.quantityPartsShipped }}</el-descriptions-item>
          </el-descriptions>

          <div class="row-between mt-4 mb-2">
            <span class="fw-semi">批次内样品（{{ currentDetail.samples.length }}）</span>
            <el-button v-if="canEdit" type="primary" plain size="small" @click="openAddSamples">
              添加样品
            </el-button>
          </div>

          <el-table :data="currentDetail.samples" size="small" empty-text="该批次尚未加入样品">
            <el-table-column prop="sampleId" label="样品ID" width="140" />
            <el-table-column label="客户样品ID" width="140">
              <template #default="{ row }">{{ row.customerSampleId || '—' }}</template>
            </el-table-column>
            <el-table-column prop="dateCode" label="Date Code" width="110">
              <template #default="{ row }">{{ row.dateCode || '—' }}</template>
            </el-table-column>
            <el-table-column prop="dbId" label="DB ID" width="100">
              <template #default="{ row }">{{ row.dbId || '—' }}</template>
            </el-table-column>
            <el-table-column label="数量" width="90">
              <template #default="{ row }">{{ row.qty ?? '—' }} {{ row.uom || '' }}</template>
            </el-table-column>
            <el-table-column prop="assemblyCenter" label="封装中心" width="110">
              <template #default="{ row }">{{ row.assemblyCenter || '—' }}</template>
            </el-table-column>
            <el-table-column prop="testCenter" label="测试中心" width="110">
              <template #default="{ row }">{{ row.testCenter || '—' }}</template>
            </el-table-column>
            <el-table-column prop="numOfDies" label="芯片数" width="90">
              <template #default="{ row }">{{ row.numOfDies ?? '—' }}</template>
            </el-table-column>
            <el-table-column label="失效类型" min-width="180" show-overflow-tooltip>
              <template #default="{ row }">{{ row.failureTypeName || '—' }}</template>
            </el-table-column>
            <el-table-column v-if="canEdit" label="操作" width="90" fixed="right">
              <template #default="{ row }">
                <el-button link type="danger" @click="removeSampleFromBatch(row.sampleId)">移出</el-button>
              </template>
            </el-table-column>
          </el-table>
        </template>
      </div>
    </el-drawer>

    <!-- Move samples from the pool into this batch -->
    <el-dialog v-model="addDialog" title="添加样品到批次" width="900px" destroy-on-close>
      <el-table
        :data="addableSamples"
        size="small"
        empty-text="该投诉没有可加入的样品（可能都已在本批次中）"
        @selection-change="(rows: any[]) => (selectedSampleIds = rows.map((r) => r.sampleId))"
      >
        <el-table-column type="selection" width="46" />
        <el-table-column prop="sampleId" label="样品ID" width="140" />
        <el-table-column prop="customerSampleId" label="客户样品ID" width="140">
          <template #default="{ row }">{{ row.customerSampleId || '—' }}</template>
        </el-table-column>
        <el-table-column label="数量" width="100">
          <template #default="{ row }">{{ row.quantity ?? '—' }} {{ row.uom || '' }}</template>
        </el-table-column>
        <el-table-column prop="failureTypeName" label="失效类型" min-width="200" show-overflow-tooltip>
          <template #default="{ row }">{{ row.failureTypeName || '—' }}</template>
        </el-table-column>
      </el-table>

      <el-divider content-position="left">
        <span class="fs-12 t-3">批次属性（统一应用到所选样品）</span>
      </el-divider>

      <el-form label-width="110px">
        <el-row :gutter="16">
          <el-col :span="8">
            <el-form-item label="Date Code">
              <el-input v-model="batchAttrs.dateCode" />
            </el-form-item>
          </el-col>
          <el-col :span="8">
            <el-form-item label="DB ID">
              <el-input v-model="batchAttrs.dbId" />
            </el-form-item>
          </el-col>
          <el-col :span="8">
            <el-form-item label="芯片数">
              <el-input-number v-model="batchAttrs.numOfDies" :min="0" :controls="false" />
            </el-form-item>
          </el-col>
        </el-row>
        <el-row :gutter="16">
          <el-col :span="8">
            <el-form-item label="封装中心">
              <el-input v-model="batchAttrs.assemblyCenter" />
            </el-form-item>
          </el-col>
          <el-col :span="8">
            <el-form-item label="测试中心">
              <el-input v-model="batchAttrs.testCenter" />
            </el-form-item>
          </el-col>
          <el-col :span="4">
            <el-form-item label="数量">
              <el-input-number v-model="batchAttrs.qty" :min="0" :controls="false" />
            </el-form-item>
          </el-col>
          <el-col :span="4">
            <el-form-item label="单位">
              <el-select v-model="batchAttrs.uom" clearable>
                <el-option v-for="u in ['PCS', 'SET', 'KG', 'M', 'LOT']" :key="u" :label="u" :value="u" />
              </el-select>
            </el-form-item>
          </el-col>
        </el-row>
      </el-form>

      <template #footer>
        <el-button @click="addDialog = false">取消</el-button>
        <el-button type="primary" :loading="addSaving" @click="confirmAddSamples">
          加入所选样品（{{ selectedSampleIds.length }}）
        </el-button>
      </template>
    </el-dialog>
  </div>
</template>
