<script setup lang="ts">
import { computed } from 'vue'

/**
 * The nine 8D stages as a single-line bar, mirroring the approved prototype.
 *
 * Colours come from the --stage-* tokens, so the "overdue" state is the same
 * red used everywhere else on the screen.
 */
const props = defineProps<{
  currentStage?: string | null
  overdueDays?: number
  closed?: boolean
}>()

const STAGES = [
  { code: 'D0', name: '问题登记' },
  { code: 'D1', name: '成立团队' },
  { code: 'D2', name: '验证与问题定义' },
  { code: 'D3', name: '遏制措施' },
  { code: 'D4', name: '根因分析' },
  { code: 'D5', name: '纠正措施' },
  { code: 'D6', name: '措施实施与验证' },
  { code: 'D7', name: '预防再发生' },
  { code: 'D8', name: '报告与结案' }
]

const currentIndex = computed(() => STAGES.findIndex((s) => s.code === props.currentStage))

function stateOf(index: number): string {
  if (props.closed) return 'done'
  if (index < currentIndex.value) return 'done'
  if (index === currentIndex.value) return props.overdueDays && props.overdueDays > 0 ? 'overdue' : 'active'
  return 'todo'
}
</script>

<template>
  <div class="stage-bar">
    <div v-for="(stage, index) in STAGES" :key="stage.code" class="stage-item" :class="'is-' + stateOf(index)" :title="stage.name">
      <span class="dot" />
      <span class="code">{{ stage.code }}</span>
      <span class="name">{{ stage.name }}</span>
    </div>
    <div v-if="overdueDays && overdueDays > 0 && !closed" class="overdue-note">超期 {{ overdueDays }} 天</div>
  </div>
</template>

<style scoped>
.stage-bar {
  display: flex;
  align-items: center;
  gap: 4px;
  flex-wrap: wrap;
  padding: 8px 12px;
  background: var(--bg-sunken);
  border-radius: var(--r-2);
}

.stage-item {
  display: flex;
  align-items: center;
  gap: 6px;
  padding: 4px 10px;
  border-radius: var(--r-full);
  background: var(--bg-surface);
  border: 1px solid var(--bd-1);
  white-space: nowrap;
}

.stage-item .dot {
  width: 7px;
  height: 7px;
  border-radius: var(--r-full);
  background: var(--stage-todo);
}

.stage-item .code {
  font-size: var(--fs-12);
  font-weight: var(--fw-semi);
  color: var(--t-3);
}

.stage-item .name {
  font-size: var(--fs-12);
  color: var(--t-3);
}

.stage-item.is-active {
  background: var(--stage-active-bg);
  border-color: var(--c-info-border);
}
.stage-item.is-active .dot { background: var(--stage-active); }
.stage-item.is-active .code,
.stage-item.is-active .name { color: var(--c-info); }

.stage-item.is-done {
  background: var(--stage-done-bg);
  border-color: var(--c-success-border);
}
.stage-item.is-done .dot { background: var(--stage-done); }
.stage-item.is-done .code,
.stage-item.is-done .name { color: var(--c-success); }

.stage-item.is-overdue {
  background: var(--stage-overdue-bg);
  border-color: var(--c-danger-border);
}
.stage-item.is-overdue .dot { background: var(--stage-overdue); }
.stage-item.is-overdue .code,
.stage-item.is-overdue .name { color: var(--c-danger); }

.overdue-note {
  margin-left: auto;
  font-size: var(--fs-12);
  font-weight: var(--fw-semi);
  color: var(--c-danger);
}
</style>
