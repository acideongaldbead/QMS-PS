<script setup lang="ts">
import { onMounted, reactive, ref } from 'vue'
import { ElMessage, ElMessageBox } from 'element-plus'
import {
  actionsApi,
  type CorrectiveActionView,
  type VerificationRequest,
  type VerificationView
} from '@/api/actions'
import { errorMessage } from '@/api/http'
import AttachmentPanel from '@/components/AttachmentPanel.vue'

/**
 * D6: implementation feedback and the effectiveness check for each corrective
 * action (requirement 3.7).
 *
 * The status is not chosen here -- the server derives it from the verdict
 * (effective -> verified, ineffective -> back for rework), which is what "the
 * result updates the status automatically" means. Evidence is attached to the
 * corrective action itself, so one action keeps one evidence set across all of
 * its verification rounds.
 */
const props = defineProps<{ complaintId: string; canVerify: boolean }>()
const emit = defineEmits<{ (e: 'refresh'): void }>()

const items = ref<CorrectiveActionView[]>([])
const loading = ref(false)

/** Verification history per action, loaded the first time its row is expanded. */
const historyByAction = reactive<Record<string, VerificationView[]>>({})

const dialogVisible = ref(false)
const saving = ref(false)
const activeActionId = ref<string | null>(null)
const form = reactive<VerificationRequest>(emptyForm())

function emptyForm(): VerificationRequest {
  return { actualCompletionDate: null, verificationResult: null, isEffective: null }
}

async function refresh() {
  loading.value = true
  try {
    items.value = await actionsApi.listActions(props.complaintId)
  } catch (e) {
    ElMessage.error('纠正措施加载失败：' + errorMessage(e))
  } finally {
    loading.value = false
  }
}

onMounted(refresh)

/** Loads the history the first time a row is expanded. */
async function onExpand(row: CorrectiveActionView, expanded: CorrectiveActionView[]) {
  if (!expanded.some((a) => a.correctiveActionId === row.correctiveActionId)) return
  if (historyByAction[row.correctiveActionId]) return
  try {
    const detail = await actionsApi.actionDetail(row.correctiveActionId)
    historyByAction[row.correctiveActionId] = detail.verifications
  } catch (e) {
    ElMessage.error('验证记录加载失败：' + errorMessage(e))
  }
}

function openRecord(row: CorrectiveActionView) {
  activeActionId.value = row.correctiveActionId
  Object.assign(form, emptyForm())
  dialogVisible.value = true
}

async function save() {
  if (!activeActionId.value) return
  // The server tolerates an empty submission, but an empty feedback line is
  // almost always a mis-click, so ask for at least one of the two free fields.
  if (!form.actualCompletionDate && !(form.verificationResult ?? '').trim()) {
    ElMessage.warning('请至少填写实际完成日期或验证结果')
    return
  }
  saving.value = true
  try {
    const detail = await actionsApi.addVerification(activeActionId.value, {
      ...form,
      verificationResult: (form.verificationResult ?? '').trim() || null
    })
    historyByAction[detail.action.correctiveActionId] = detail.verifications
    ElMessage.success('验证已录入')
    dialogVisible.value = false
    await refresh()
    emit('refresh')
  } catch (e) {
    ElMessage.error(errorMessage(e))
  } finally {
    saving.value = false
  }
}

async function remove(row: CorrectiveActionView, verification: VerificationView) {
  try {
    await ElMessageBox.confirm(
      '确定删除这条验证记录？删除不会自动回退措施状态，如需调整请再录入一条验证。',
      '删除验证记录',
      { type: 'warning' }
    )
  } catch {
    return
  }
  try {
    const detail = await actionsApi.removeVerification(row.correctiveActionId, verification.verificationId)
    historyByAction[detail.action.correctiveActionId] = detail.verifications
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

function effectivenessLabel(value?: boolean | null): string {
  if (value === true) return '有效'
  if (value === false) return '无效'
  return '未判定'
}

function effectivenessTagType(value?: boolean | null): string {
  if (value === true) return 'success'
  if (value === false) return 'danger'
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
        负责人在此反馈措施的实施情况并验证有效性；有效性判定会由系统自动更新措施状态，证据附件挂在对应措施下。
      </span>
    </div>

    <el-table
      :data="items"
      v-loading="loading"
      size="small"
      row-key="correctiveActionId"
      empty-text="尚无纠正措施（请先在 D5 制定）"
      @expand-change="onExpand"
    >
      <el-table-column type="expand">
        <template #default="{ row }">
          <div class="expand-body">
            <div class="row-between mb-2">
              <span class="fs-12 t-3">
                验证记录（{{ (historyByAction[row.correctiveActionId] || []).length }}）
              </span>
              <el-button
                v-if="canVerify"
                size="small"
                type="primary"
                plain
                @click="openRecord(row)"
              >
                记录验证
              </el-button>
            </div>

            <el-table
              :data="historyByAction[row.correctiveActionId] || []"
              size="small"
              empty-text="尚未录入验证"
            >
              <el-table-column label="实际完成日期" width="130">
                <template #default="{ row: v }">{{ v.actualCompletionDate || '—' }}</template>
              </el-table-column>
              <el-table-column label="验证结果" min-width="240" show-overflow-tooltip>
                <template #default="{ row: v }">{{ v.verificationResult || '—' }}</template>
              </el-table-column>
              <el-table-column label="有效性" width="100">
                <template #default="{ row: v }">
                  <el-tag size="small" :type="effectivenessTagType(v.isEffective)">
                    {{ effectivenessLabel(v.isEffective) }}
                  </el-tag>
                </template>
              </el-table-column>
              <el-table-column label="验证人" width="100">
                <template #default="{ row: v }">{{ v.verifiedByName || '—' }}</template>
              </el-table-column>
              <el-table-column label="验证时间" width="150">
                <template #default="{ row: v }">{{ formatTime(v.verifiedAt) }}</template>
              </el-table-column>
              <el-table-column v-if="canVerify" label="操作" width="80" fixed="right">
                <template #default="{ row: v }">
                  <el-button link type="danger" @click="remove(row, v)">删除</el-button>
                </template>
              </el-table-column>
            </el-table>

            <div class="mt-3">
              <div class="fs-12 t-3 mb-2">证据附件</div>
              <AttachmentPanel
                biz-type="CorrectiveAction"
                :biz-id="row.correctiveActionId"
                :readonly="!canVerify"
              />
            </div>
          </div>
        </template>
      </el-table-column>

      <el-table-column prop="correctiveActionId" label="措施ID" width="140" />
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
      <el-table-column label="最近反馈" width="120">
        <template #default="{ row }">{{ row.actualCompletionDate || '—' }}</template>
      </el-table-column>
      <el-table-column label="验证数" width="80">
        <template #default="{ row }">{{ row.verificationCount }}</template>
      </el-table-column>
    </el-table>

    <el-dialog v-model="dialogVisible" title="记录措施验证" width="640px" destroy-on-close>
      <el-form :model="form" label-width="120px">
        <el-form-item label="实际完成日期">
          <el-date-picker
            v-model="form.actualCompletionDate"
            type="date"
            value-format="YYYY-MM-DD"
            style="width: 100%"
          />
        </el-form-item>
        <el-form-item label="验证结果">
          <el-input
            v-model="form.verificationResult"
            type="textarea"
            :rows="3"
            resize="none"
            placeholder="实施情况、验证方式与结论"
          />
        </el-form-item>
        <el-form-item label="有效性">
          <el-radio-group v-model="form.isEffective">
            <el-radio :value="null">仅记录进展</el-radio>
            <el-radio :value="true">有效</el-radio>
            <el-radio :value="false">无效，需返工</el-radio>
          </el-radio-group>
        </el-form-item>
      </el-form>
      <el-alert
        type="info"
        :closable="false"
        show-icon
        title="判定后措施状态自动更新：有效→已验证；无效→验证不通过（返工）；仅记录进展→已实施。"
      />
      <template #footer>
        <el-button @click="dialogVisible = false">取消</el-button>
        <el-button type="primary" :loading="saving" @click="save">保存</el-button>
      </template>
    </el-dialog>
  </div>
</template>

<style scoped>
.expand-body {
  padding: 8px 24px 12px;
  background: var(--bg-sunken);
}
</style>
