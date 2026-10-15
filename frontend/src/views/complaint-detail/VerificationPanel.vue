<script setup lang="ts">
import { computed, onMounted, reactive, ref } from 'vue'
import { ElMessage, ElMessageBox } from 'element-plus'
import {
  verificationApi,
  TASK_STATUSES,
  type ResultRequest,
  type ResultView,
  type TaskRequest,
  type TaskView
} from '@/api/verification'
import { errorMessage } from '@/api/http'
import { useAuthStore } from '@/stores/auth'
import { useMetaStore } from '@/stores/meta'
import RowAction from '@/components/RowAction.vue'
import FailureTypeCascade from '@/components/FailureTypeCascade.vue'

/**
 * D2: verification and problem definition (requirement 3.3).
 *
 * Tasks, their result lines, and the validity conclusion that decides whether the
 * complaint continues or closes. The conclusion moves the complaint, so the
 * parent is asked to reload once it is made.
 */
const props = defineProps<{
  complaintId: string
  /** null until the D2 conclusion has been given. */
  isValid: boolean | null
  closeDate?: string | null
  closeReasonName?: string | null
  /** The complaint's samples, for the "which sample is this task about" picker. */
  samples: { sampleId: string; value: { customerSampleId?: string | null } }[]
  canVerify: boolean
}>()

const emit = defineEmits<{ (e: 'refresh'): void }>()
const meta = useMetaStore()

const tasks = ref<TaskView[]>([])
const loading = ref(false)
const resultsByTask = reactive<Record<string, ResultView[]>>({})

const taskDialog = ref(false)
const taskSaving = ref(false)
const editingTaskId = ref<string | null>(null)
const taskForm = reactive<TaskRequest>(emptyTask())

const resultDialog = ref(false)
const resultSaving = ref(false)
const resultTaskId = ref<string | null>(null)
const resultForm = reactive<ResultRequest>(emptyResult())

const batchDialog = ref(false)
const batchSaving = ref(false)
const batchTaskId = ref<string | null>(null)
const batchRows = ref<ResultRequest[]>([])

const validitySaving = ref(false)
const validityForm = reactive<{ valid: boolean | null; conclusion: string | null }>({
  valid: null,
  conclusion: null
})
/** The second-confirmation dialog: nothing is submitted until it is accepted. */
const confirmDialog = ref(false)
/** Set while a determined verdict is being overridden, which only an admin may do. */
const changingDecision = ref(false)

const auth = useAuthStore()
const isAdmin = computed(() => auth.can('admin.all'))

/** 无效 always closes as "complaint not valid"; the server accepts nothing else. */
const INVALID_REASON_CODE = 'CLOSE_INVALID'

function emptyTask(): TaskRequest {
  return {
    sampleId: null,
    taskOwnerId: '',
    plannedStartDate: null,
    targetCompletionDate: '',
    taskStatus: null,
    creationMode: 'MANUAL'
  }
}

function emptyResult(): ResultRequest {
  return {
    testItem: '',
    failureTypeL1Code: null,
    failureTypeL2Code: null,
    failureTypeL3Code: null,
    resultConclusion: null
  }
}

async function refresh() {
  loading.value = true
  try {
    tasks.value = await verificationApi.listTasks(props.complaintId)
  } catch (e) {
    ElMessage.error('验证任务加载失败：' + errorMessage(e))
  } finally {
    loading.value = false
  }
}

onMounted(refresh)

// ------------------------------------------------------------------ tasks

function openCreateTask() {
  editingTaskId.value = null
  Object.assign(taskForm, emptyTask())
  taskDialog.value = true
}

function openEditTask(row: TaskView) {
  editingTaskId.value = row.taskId
  Object.assign(taskForm, {
    sampleId: row.sampleId,
    taskOwnerId: row.taskOwnerId,
    plannedStartDate: row.plannedStartDate,
    targetCompletionDate: row.targetCompletionDate,
    taskStatus: row.taskStatus,
    creationMode: row.creationMode
  })
  taskDialog.value = true
}

async function saveTask() {
  taskSaving.value = true
  try {
    if (editingTaskId.value) {
      const detail = await verificationApi.updateTask(editingTaskId.value, { ...taskForm })
      resultsByTask[detail.task.taskId] = detail.results
      ElMessage.success('任务已更新')
    } else {
      const detail = await verificationApi.createTask(props.complaintId, { ...taskForm })
      resultsByTask[detail.task.taskId] = detail.results
      ElMessage.success('已创建验证任务：' + detail.task.taskId)
    }
    taskDialog.value = false
    await refresh()
    emit('refresh')
  } catch (e) {
    ElMessage.error(errorMessage(e))
  } finally {
    taskSaving.value = false
  }
}

async function removeTask(row: TaskView) {
  try {
    await ElMessageBox.confirm(`确定删除验证任务 ${row.taskId}？`, '删除任务', { type: 'warning' })
  } catch {
    return
  }
  try {
    await verificationApi.removeTask(row.taskId)
    delete resultsByTask[row.taskId]
    ElMessage.success('已删除')
    await refresh()
  } catch (e) {
    ElMessage.error(errorMessage(e))
  }
}

/** Loads the result lines the first time a row is expanded. */
async function onExpand(row: TaskView, expanded: TaskView[]) {
  if (!expanded.some((t) => t.taskId === row.taskId)) return
  if (resultsByTask[row.taskId]) return
  try {
    const detail = await verificationApi.taskDetail(row.taskId)
    resultsByTask[row.taskId] = detail.results
  } catch (e) {
    ElMessage.error('验证结果加载失败：' + errorMessage(e))
  }
}

// ------------------------------------------------------------------ results

function openSingleResult(taskId: string) {
  resultTaskId.value = taskId
  Object.assign(resultForm, emptyResult())
  resultDialog.value = true
}

async function saveSingleResult() {
  if (!resultTaskId.value) return
  resultSaving.value = true
  try {
    const detail = await verificationApi.addResult(resultTaskId.value, { ...resultForm })
    resultsByTask[detail.task.taskId] = detail.results
    ElMessage.success('验证结果已录入')
    resultDialog.value = false
    await refresh()
  } catch (e) {
    ElMessage.error(errorMessage(e))
  } finally {
    resultSaving.value = false
  }
}

function openBatch(taskId: string) {
  batchTaskId.value = taskId
  batchRows.value = [emptyResult()]
  batchDialog.value = true
}

function addBatchRow() {
  batchRows.value.push(emptyResult())
}

function removeBatchRow(index: number) {
  batchRows.value.splice(index, 1)
}

async function saveBatch() {
  if (!batchTaskId.value) return
  batchSaving.value = true
  try {
    const detail = await verificationApi.addBatchResults(batchTaskId.value, batchRows.value)
    resultsByTask[detail.task.taskId] = detail.results
    ElMessage.success(`已批量录入 ${batchRows.value.length} 条验证结果`)
    batchDialog.value = false
    await refresh()
  } catch (e) {
    ElMessage.error(errorMessage(e))
  } finally {
    batchSaving.value = false
  }
}

async function removeResult(taskId: string, resultId: number) {
  try {
    const detail = await verificationApi.removeResult(taskId, resultId)
    resultsByTask[detail.task.taskId] = detail.results
    ElMessage.success('已删除')
    await refresh()
  } catch (e) {
    ElMessage.error(errorMessage(e))
  }
}

// ------------------------------------------------------------------ validity

/**
 * Opens the second confirmation. Nothing is sent until the user accepts it there,
 * because the verdict is a one-way door for everyone except an administrator.
 */
function submitValidity() {
  if (validityForm.valid === null) {
    ElMessage.warning('请先给出投诉是否有效的结论')
    return
  }
  confirmDialog.value = true
}

async function confirmValidity() {
  validitySaving.value = true
  try {
    const outcome = await verificationApi.setValidity(props.complaintId, {
      valid: validityForm.valid!,
      reasonCode: validityForm.valid ? null : INVALID_REASON_CODE,
      conclusion: validityForm.conclusion
    })
    const changed = changingDecision.value
    ElMessage.success(
      outcome.valid
        ? (changed ? '判定已改为有效，投诉已重新打开并进入 D3' : '已判定为有效，投诉进入 D3')
        : (changed ? '判定已改为无效，投诉已结案' : '已判定为无效，投诉已结案（' + outcome.closeDate + '）')
    )
    confirmDialog.value = false
    changingDecision.value = false
    emit('refresh')
  } catch (e) {
    ElMessage.error(errorMessage(e))
  } finally {
    validitySaving.value = false
  }
}

/** Administrators may override a determined verdict; everyone else may not. */
function startChangeDecision() {
  changingDecision.value = true
  validityForm.valid = props.isValid ?? null
  validityForm.conclusion = null
}

function cancelChangeDecision() {
  changingDecision.value = false
  validityForm.valid = props.isValid ?? null
  validityForm.conclusion = null
}

const decided = computed(() => props.isValid !== null && props.isValid !== undefined)

/** Options for the task dialog's sample picker. */
const samplesOfComplaint = computed(() =>
  props.samples.map((s) => ({
    sampleId: s.sampleId,
    label: s.value.customerSampleId ? `${s.sampleId}（${s.value.customerSampleId}）` : s.sampleId
  }))
)

// ------------------------------------------------------------------ helpers

/** Flattens the failure type tree for name lookups in the batch table. */
const failureTypeNames = computed(() => {
  const flat: Record<string, string> = {}
  const walk = (nodes: typeof meta.failureTypes) => {
    for (const node of nodes) {
      flat[node.code] = node.name
      if (node.children?.length) walk(node.children)
    }
  }
  walk(meta.failureTypes)
  return flat
})

function level2OptionsFor(row: ResultRequest) {
  const l1 = meta.failureTypes.find((t) => t.code === row.failureTypeL1Code)
  return l1?.children ?? []
}

function level3OptionsFor(row: ResultRequest) {
  const l2 = level2OptionsFor(row).find((t) => t.code === row.failureTypeL2Code)
  return l2?.children ?? []
}

function onBatchLevel1(row: ResultRequest) {
  row.failureTypeL2Code = null
  row.failureTypeL3Code = null
}

function onBatchLevel2(row: ResultRequest) {
  row.failureTypeL3Code = null
}
</script>

<template>
  <div>
    <!-- ---------------------------------------------------------- tasks -->
    <div class="row-between mb-3">
      <span class="fs-12 t-3">
        验证任务由质量工程师创建与录入；任务目标日期晚于投诉目标日期时会给出提示。
      </span>
      <el-button v-if="canVerify" type="primary" plain @click="openCreateTask">新增验证任务</el-button>
    </div>

    <el-table :data="tasks" v-loading="loading" size="small" row-key="taskId" empty-text="尚未创建验证任务">
      <el-table-column type="expand">
        <template #default="{ row }">
          <div class="expand-body">
            <div class="row-between mb-2">
              <span class="fs-12 t-3">验证结果（{{ (resultsByTask[row.taskId] || []).length }}）</span>
              <span v-if="canVerify">
                <el-button size="small" @click="openSingleResult(row.taskId)">逐个录入</el-button>
                <el-button size="small" type="primary" plain @click="openBatch(row.taskId)">批量录入</el-button>
              </span>
            </div>
            <el-table :data="resultsByTask[row.taskId] || []" size="small" empty-text="尚未录入结果">
              <el-table-column prop="testItem" label="测试项" width="150" />
              <el-table-column label="失效类型" min-width="220">
                <template #default="{ row: r }">
                  {{ r.failureTypeL3Name || r.failureTypeL2Name || r.failureTypeL1Name || '—' }}
                </template>
              </el-table-column>
              <el-table-column prop="resultConclusion" label="结论" min-width="220" show-overflow-tooltip />
              <el-table-column label="录入方式" width="100">
                <template #default="{ row: r }">
                  <el-tag size="small" :type="r.entryMode === 'BATCH' ? 'info' : 'success'">
                    {{ r.entryMode === 'BATCH' ? '批量' : '逐个' }}
                  </el-tag>
                </template>
              </el-table-column>
              <el-table-column prop="recordedByName" label="录入人" width="100" />
              <el-table-column label="录入时间" width="160">
                <template #default="{ row: r }">
                  {{ r.recordedAt ? String(r.recordedAt).replace('T', ' ').slice(0, 16) : '' }}
                </template>
              </el-table-column>
              <el-table-column v-if="canVerify" label="操作" width="72" fixed="right">
                <template #default="{ row: r }">
                  <span class="row-acts">
                    <RowAction act="delete" icon="trash" tone="danger" label="删除" @click="removeResult(row.taskId, r.resultId)" />
                  </span>
                </template>
              </el-table-column>
            </el-table>
          </div>
        </template>
      </el-table-column>
      <el-table-column prop="taskId" label="任务ID" width="140" />
      <el-table-column label="样品" width="150">
        <template #default="{ row }">{{ row.sampleCustomerSampleId || row.sampleId || '整单' }}</template>
      </el-table-column>
      <el-table-column prop="taskOwnerName" label="负责人" width="100" />
      <el-table-column label="计划开始" width="120">
        <template #default="{ row }">{{ row.plannedStartDate || '—' }}</template>
      </el-table-column>
      <el-table-column label="目标完成" width="150">
        <template #default="{ row }">
          <span :title="row.targetWarning || ''" :class="{ 't-danger': !!row.targetWarning }">
            {{ row.targetCompletionDate }}
            <el-tooltip v-if="row.targetWarning" :content="row.targetWarning" placement="top">
              <span class="warn-mark">!</span>
            </el-tooltip>
          </span>
        </template>
      </el-table-column>
      <el-table-column label="状态" width="100">
        <template #default="{ row }">
          <el-tag size="small" :type="row.taskStatus === 'VERIF_DONE' ? 'success' : 'info'">
            {{ row.taskStatusName || row.taskStatus }}
          </el-tag>
        </template>
      </el-table-column>
      <el-table-column label="结果数" width="80">
        <template #default="{ row }">{{ row.resultCount }}</template>
      </el-table-column>
      <el-table-column v-if="canVerify" label="操作" width="120" fixed="right">
        <template #default="{ row }">
          <span class="row-acts">
            <RowAction act="edit" icon="pencil" label="编辑" @click="openEditTask(row)" />
            <RowAction act="delete" icon="trash" tone="danger" label="删除" @click="removeTask(row)" />
          </span>
        </template>
      </el-table-column>
    </el-table>

    <!-- ---------------------------------------------------------- validity -->
    <el-card shadow="never" class="mt-4">
      <template #header>
        <span class="fw-semi">投诉有效性判定</span>
        <span class="fs-12 t-3" style="margin-left: 8px">
          判定前请先完成验证任务；判定提交后仅管理员可修改
        </span>
      </template>

      <!-- Already decided -->
      <template v-if="decided">
        <el-alert
          :type="isAdmin ? 'info' : 'success'"
          :closable="false"
          show-icon
          :title="'该投诉已判定为「' + (isValid ? '有效' : '无效') + '」'
            + (isAdmin ? '。作为管理员，你可以修改该判定。' : '，只有管理员可以修改。')"
        />
        <el-descriptions :column="3" border size="small" class="mt-3">
          <el-descriptions-item label="判定结论">
            <el-tag :type="isValid ? 'success' : 'danger'" size="small">
              {{ isValid ? '有效' : '无效' }}
            </el-tag>
          </el-descriptions-item>
          <el-descriptions-item label="结案日期">{{ closeDate || '—' }}</el-descriptions-item>
          <el-descriptions-item label="结案原因">{{ closeReasonName || '—' }}</el-descriptions-item>
        </el-descriptions>

        <template v-if="isAdmin">
          <div v-if="!changingDecision" class="mt-3">
            <el-button @click="startChangeDecision">修改判定</el-button>
          </div>
          <template v-else>
            <el-alert
              class="mt-3 mb-3"
              type="warning"
              :closable="false"
              show-icon
              title="你正在修改一个已提交的判定。把「无效」改为「有效」会重新打开该投诉；把「有效」改为「无效」会直接结案。"
            />
            <el-form label-width="130px">
              <el-form-item label="判定结论" required>
                <el-radio-group v-model="validityForm.valid">
                  <el-radio-button :value="true">有效</el-radio-button>
                  <el-radio-button :value="false">无效</el-radio-button>
                </el-radio-group>
              </el-form-item>
              <el-form-item label="验证结论">
                <el-input
                  v-model="validityForm.conclusion"
                  type="textarea"
                  :rows="3"
                  resize="none"
                  placeholder="留空则不覆盖原有结论"
                />
              </el-form-item>
            </el-form>
            <div class="row-end gap-2">
              <el-button @click="cancelChangeDecision">取消</el-button>
              <el-button type="primary" @click="submitValidity">提交修改</el-button>
            </div>
          </template>
        </template>
      </template>

      <!-- Not decided yet -->
      <template v-else-if="canVerify">
        <el-form label-width="130px">
          <el-form-item label="判定结论" required>
            <el-radio-group v-model="validityForm.valid">
              <el-radio-button :value="true">有效</el-radio-button>
              <el-radio-button :value="false">无效</el-radio-button>
            </el-radio-group>
          </el-form-item>
          <el-form-item label="结案原因">
            <el-input
              :model-value="validityForm.valid === false ? '投诉不成立' : '—'"
              disabled
              placeholder="判定为无效时固定为「投诉不成立」"
            />
          </el-form-item>
          <el-form-item label="验证结论">
            <el-input
              v-model="validityForm.conclusion"
              type="textarea"
              :rows="3"
              resize="none"
              placeholder="写入失效描述的「投诉/分析结论」，8D 报告会读取该字段"
            />
          </el-form-item>
        </el-form>

        <el-alert
          v-if="validityForm.valid === false"
          type="warning"
          :closable="false"
          show-icon
          title="判定为「无效」会直接关闭该投诉单（阶段跳到 D8、记录结案日期与原因）。提交前会再次确认。"
        />
        <el-alert
          v-else-if="validityForm.valid === true"
          type="info"
          :closable="false"
          show-icon
          title="判定为「有效」后，投诉进入 D3 遏制措施。提交前会再次确认。"
        />

        <div class="mt-4 row-end">
          <el-button type="primary" :disabled="validityForm.valid === null" @click="submitValidity">
            提交判定
          </el-button>
        </div>
      </template>

      <el-empty v-else description="尚无权限进行有效性判定" />
    </el-card>

    <!-- ---------------------------------------------- second confirmation -->
    <el-dialog v-model="confirmDialog" title="确认提交有效性判定" width="560px" destroy-on-close>
      <div class="confirm-body">
        <p class="confirm-line">
          判定结论：
          <el-tag :type="validityForm.valid ? 'success' : 'danger'">
            {{ validityForm.valid ? '有效' : '无效' }}
          </el-tag>
          <el-tag v-if="changingDecision" type="warning" style="margin-left: 8px">修改已提交的判定</el-tag>
        </p>

        <ul class="confirm-list">
          <li v-if="validityForm.valid">
            投诉将进入 <b>D3 遏制措施</b><span v-if="changingDecision">，若原判定为无效，该投诉会被重新打开</span>。
          </li>
          <li v-else>
            投诉将 <b class="t-danger">直接结案</b>：阶段跳到 D8，记录结案日期与结案原因「投诉不成立」。
          </li>
          <li>提交后<b>只有管理员可以修改</b>该判定。</li>
          <li v-if="validityForm.conclusion">验证结论将写入失效描述的「投诉/分析结论」。</li>
        </ul>

        <p v-if="validityForm.conclusion" class="confirm-conclusion">
          {{ validityForm.conclusion }}
        </p>
      </div>
      <template #footer>
        <el-button @click="confirmDialog = false">取消</el-button>
        <el-button
          :type="validityForm.valid ? 'primary' : 'danger'"
          :loading="validitySaving"
          @click="confirmValidity"
        >
          确认提交
        </el-button>
      </template>
    </el-dialog>

    <!-- ---------------------------------------------------------- task dialog -->
    <el-dialog
      v-model="taskDialog"
      :title="editingTaskId ? '编辑验证任务 ' + editingTaskId : '新增验证任务'"
      width="760px"
      destroy-on-close
    >
      <el-form :model="taskForm" label-width="130px">
        <el-row :gutter="16">
          <el-col :span="12">
            <el-form-item label="关联样品">
              <el-select v-model="taskForm.sampleId" placeholder="留空表示整单" clearable>
                <el-option
                  v-for="s in samplesOfComplaint"
                  :key="s.sampleId"
                  :label="s.label"
                  :value="s.sampleId"
                />
              </el-select>
            </el-form-item>
          </el-col>
          <el-col :span="12">
            <el-form-item label="任务负责人" required>
              <el-select v-model="taskForm.taskOwnerId" filterable placeholder="请选择">
                <el-option v-for="e in meta.employees" :key="e.id" :label="e.name" :value="e.id">
                  <span>{{ e.name }}</span>
                  <span class="option-sub">{{ e.jobTitle || e.id }}</span>
                </el-option>
              </el-select>
            </el-form-item>
          </el-col>
        </el-row>
        <el-row :gutter="16">
          <el-col :span="12">
            <el-form-item label="计划开始日期">
              <el-date-picker v-model="taskForm.plannedStartDate" type="date" value-format="YYYY-MM-DD" />
            </el-form-item>
          </el-col>
          <el-col :span="12">
            <el-form-item label="目标完成日期" required>
              <el-date-picker v-model="taskForm.targetCompletionDate" type="date" value-format="YYYY-MM-DD" />
            </el-form-item>
          </el-col>
        </el-row>
        <el-form-item label="任务状态">
          <el-select v-model="taskForm.taskStatus" placeholder="留空则按计划日期自动判定" clearable>
            <el-option v-for="s in TASK_STATUSES" :key="s.code" :label="s.label" :value="s.code" />
          </el-select>
        </el-form-item>
      </el-form>
      <template #footer>
        <el-button @click="taskDialog = false">取消</el-button>
        <el-button type="primary" :loading="taskSaving" @click="saveTask">保存</el-button>
      </template>
    </el-dialog>

    <!-- ---------------------------------------------------------- single result -->
    <el-dialog v-model="resultDialog" title="逐个录入验证结果" width="900px" destroy-on-close>
      <el-form :model="resultForm" label-width="130px">
        <el-form-item label="测试项" required>
          <el-input v-model="resultForm.testItem" placeholder="如 X-Ray、电性测试" />
        </el-form-item>
        <FailureTypeCascade :model="resultForm" />
        <el-form-item label="结果结论">
          <el-input v-model="resultForm.resultConclusion" type="textarea" :rows="3" resize="none" />
        </el-form-item>
      </el-form>
      <template #footer>
        <el-button @click="resultDialog = false">取消</el-button>
        <el-button type="primary" :loading="resultSaving" @click="saveSingleResult">保存</el-button>
      </template>
    </el-dialog>

    <!-- ---------------------------------------------------------- batch results -->
    <el-dialog v-model="batchDialog" title="批量录入验证结果" width="98%" destroy-on-close>
      <div class="row-between mb-2">
        <span class="fs-12 t-3">同一任务的多条测试结果一次提交；任意一行不合格则整批不会保存。</span>
        <el-button size="small" @click="addBatchRow">添加一行</el-button>
      </div>
      <el-table :data="batchRows" size="small">
        <el-table-column label="测试项" width="180">
          <template #default="{ row }">
            <el-input v-model="row.testItem" size="small" placeholder="必填" />
          </template>
        </el-table-column>
        <el-table-column label="失效类型 一级" width="200">
          <template #default="{ row }">
            <el-select v-model="row.failureTypeL1Code" size="small" clearable placeholder="请选择" @change="onBatchLevel1(row)">
              <el-option v-for="t in meta.failureTypes" :key="t.code" :label="t.name" :value="t.code" />
            </el-select>
          </template>
        </el-table-column>
        <el-table-column label="二级" width="200">
          <template #default="{ row }">
            <el-select
              v-model="row.failureTypeL2Code"
              size="small"
              clearable
              placeholder="请先选择一级"
              :disabled="!row.failureTypeL1Code"
              @change="onBatchLevel2(row)"
            >
              <el-option v-for="t in level2OptionsFor(row)" :key="t.code" :label="t.name" :value="t.code" />
            </el-select>
          </template>
        </el-table-column>
        <el-table-column label="三级" width="220">
          <template #default="{ row }">
            <el-select
              v-model="row.failureTypeL3Code"
              size="small"
              clearable
              placeholder="请先选择二级"
              :disabled="!row.failureTypeL2Code"
            >
              <el-option v-for="t in level3OptionsFor(row)" :key="t.code" :label="t.name" :value="t.code" />
            </el-select>
          </template>
        </el-table-column>
        <el-table-column label="结论" min-width="220">
          <template #default="{ row }">
            <el-input v-model="row.resultConclusion" size="small" />
          </template>
        </el-table-column>
        <el-table-column label="操作" width="72">
          <template #default="{ $index }">
            <span class="row-acts">
              <RowAction act="remove" icon="arrowRightFromLine" tone="danger" label="移除" @click="removeBatchRow($index)" />
            </span>
          </template>
        </el-table-column>
      </el-table>
      <template #footer>
        <el-button @click="batchDialog = false">取消</el-button>
        <el-button type="primary" :loading="batchSaving" @click="saveBatch">
          提交 {{ batchRows.length }} 条
        </el-button>
      </template>
    </el-dialog>
  </div>
</template>

<style scoped>
.expand-body {
  padding: 8px 24px 12px;
  background: var(--bg-sunken);
}
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
.option-sub {
  float: right;
  margin-left: 16px;
  color: var(--t-4);
  font-size: var(--fs-12);
}
.row-end {
  display: flex;
  justify-content: flex-end;
  gap: var(--sp-2);
}

/* Second-confirmation dialog body. base.css removes list styling globally, so the
   bullet list has to ask for it back. */
.confirm-body {
  font-size: var(--fs-13);
  color: var(--t-2);
}
.confirm-line {
  margin: 0 0 var(--sp-3);
}
.confirm-list {
  margin: 0;
  padding-left: 20px;
  list-style: disc;
}
.confirm-list li {
  margin-bottom: 6px;
  line-height: var(--lh-base);
}
.confirm-conclusion {
  margin: var(--sp-3) 0 0;
  padding: 8px 12px;
  background: var(--bg-sunken);
  border-radius: var(--r-2);
  color: var(--t-3);
}
</style>
