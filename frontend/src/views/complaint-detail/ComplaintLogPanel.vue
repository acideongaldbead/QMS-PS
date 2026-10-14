<script setup lang="ts">
import { onMounted, ref } from 'vue'
import { ElMessage } from 'element-plus'
import { errorMessage } from '@/api/http'
import { complaintApi, type LogEntry } from '@/api/complaints'

const props = defineProps<{ complaintId: string }>()

const entries = ref<LogEntry[]>([])
const loading = ref(false)

function formatTime(value?: string | null) {
  return value ? value.replace('T', ' ').slice(0, 19) : '—'
}

/** Maps the server's tone values onto the timeline's dot classes. */
function dotClass(tone: string) {
  if (tone === 'done') return 'is-done'
  if (tone === 'warn') return 'is-warn'
  return ''
}

async function load() {
  loading.value = true
  try {
    entries.value = await complaintApi.logs(props.complaintId)
  } catch (e) {
    ElMessage.error('日志加载失败：' + errorMessage(e))
  } finally {
    loading.value = false
  }
}

onMounted(load)
</script>

<template>
  <div v-loading="loading">
    <div class="table-toolbar" style="padding-left: 0">
      <span class="fs-12 t-3">
        共 <b class="t-1 num">{{ entries.length }}</b> 条记录（流程操作与对外沟通按时间倒序）
      </span>
    </div>

    <div v-if="entries.length" class="timeline">
      <div v-for="(entry, index) in entries" :key="index" class="tl-item" :class="dotClass(entry.tone)">
        <span class="tl-dot"></span>
        <div class="tl-time">
          {{ formatTime(entry.at) }} · {{ entry.actorName || '—' }}
          <span v-if="entry.kind === 'COMMUNICATION'" class="badge badge-info" style="margin-left: 6px">
            沟通
          </span>
        </div>
        <div class="tl-title">{{ entry.actionLabel }}</div>
        <div v-if="entry.detail" class="tl-desc">{{ entry.detail }}</div>
      </div>
    </div>

    <el-empty v-else-if="!loading" description="该投诉单暂无日志记录" />
  </div>
</template>
