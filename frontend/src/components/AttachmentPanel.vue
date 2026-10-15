<script setup lang="ts">
import { computed, onMounted, ref } from 'vue'
import { ElMessage, ElMessageBox } from 'element-plus'
import {
  attachmentApi,
  formatBytes,
  type AttachmentView,
  type UploadRules
} from '@/api/attachments'
import { errorMessage } from '@/api/http'
import RowAction from '@/components/RowAction.vue'

/**
 * Attachments for one business record. Reused by the registration result panel
 * and by the complaint detail page.
 *
 * The whitelist and size ceiling come from the server rather than being repeated
 * here, so the two can never drift apart. Files are still checked again on the
 * server -- this side is only for immediate feedback.
 */
const props = withDefaults(
  defineProps<{ bizType: string; bizId: string; readonly?: boolean }>(),
  { readonly: false }
)

const items = ref<AttachmentView[]>([])
const rules = ref<UploadRules>({ allowedExtensions: [], maxBytes: 0 })
const loading = ref(false)
const uploading = ref(false)

const acceptAttr = computed(() => rules.value.allowedExtensions.map((e) => `.${e}`).join(','))
const hint = computed(
  () =>
    `允许 ${rules.value.allowedExtensions.join(' / ')}，单文件不超过 ${formatBytes(rules.value.maxBytes)}`
)

async function refresh() {
  loading.value = true
  try {
    items.value = await attachmentApi.list(props.bizType, props.bizId)
  } catch (e) {
    ElMessage.error('附件列表加载失败：' + errorMessage(e))
  } finally {
    loading.value = false
  }
}

onMounted(async () => {
  try {
    rules.value = await attachmentApi.rules()
  } catch {
    /* the hint simply stays sparse */
  }
  await refresh()
})

/** Rejects locally what the server would reject anyway, to save a round trip. */
function precheck(file: File): string | null {
  const ext = file.name.includes('.') ? file.name.split('.').pop()!.toLowerCase() : ''
  if (!rules.value.allowedExtensions.includes(ext)) {
    return `不支持的文件类型 .${ext}`
  }
  if (file.size > rules.value.maxBytes) {
    return `文件超过 ${formatBytes(rules.value.maxBytes)}`
  }
  return null
}

async function onFileChosen(file: File) {
  const problem = precheck(file)
  if (problem) {
    ElMessage.error(problem)
    return
  }
  uploading.value = true
  try {
    const result = await attachmentApi.upload(props.bizType, props.bizId, file)
    ElMessage.success(`已上传：${result.attachment.fileName}（${result.scanResult}）`)
    await refresh()
  } catch (e) {
    ElMessage.error(errorMessage(e))
  } finally {
    uploading.value = false
  }
}

async function onRemove(item: AttachmentView) {
  try {
    await ElMessageBox.confirm(`确定删除附件「${item.fileName}」？`, '删除附件', {
      type: 'warning'
    })
  } catch {
    return
  }
  try {
    await attachmentApi.remove(item.attachmentId)
    ElMessage.success('已删除')
    await refresh()
  } catch (e) {
    ElMessage.error(errorMessage(e))
  }
}

async function onDownload(item: AttachmentView) {
  try {
    await attachmentApi.downloadAndSave(item.attachmentId, item.fileName)
  } catch (e) {
    ElMessage.error('下载失败：' + errorMessage(e))
  }
}
</script>

<template>
  <div>
    <div class="row-between mb-2">
      <span class="fs-12 t-3">{{ hint }}</span>
      <el-upload
        v-if="!readonly"
        :show-file-list="false"
        :auto-upload="false"
        :accept="acceptAttr"
        @change="(f: any) => onFileChosen(f.raw as File)"
      >
        <el-button type="primary" plain :loading="uploading">上传附件</el-button>
      </el-upload>
    </div>

    <el-table :data="items" v-loading="loading" size="small" empty-text="暂无附件">
      <el-table-column prop="fileName" label="文件名" min-width="220" show-overflow-tooltip />
      <el-table-column label="大小" width="100">
        <template #default="{ row }">{{ formatBytes(row.fileSize) }}</template>
      </el-table-column>
      <el-table-column prop="fileType" label="类型" width="200" show-overflow-tooltip />
      <el-table-column prop="uploadedByName" label="上传人" width="100" />
      <el-table-column label="上传时间" width="180">
        <template #default="{ row }">
          {{ row.uploadedAt ? String(row.uploadedAt).replace('T', ' ').slice(0, 19) : '' }}
        </template>
      </el-table-column>
      <el-table-column label="操作" width="96" fixed="right">
        <template #default="{ row }">
          <span class="row-acts">
            <RowAction act="download" icon="download" label="下载" @click="onDownload(row)" />
            <RowAction v-if="!readonly" act="delete" icon="trash" tone="danger" label="删除" @click="onRemove(row)" />
          </span>
        </template>
      </el-table-column>
    </el-table>
  </div>
</template>
