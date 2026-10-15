<script setup lang="ts">
import QmsIcon from '@/components/QmsIcon.vue'

/**
 * One action in a table's 操作 column, drawn as an icon.
 *
 * The label lives in a hover tooltip. That also keeps the column narrow enough
 * that a row with four actions still fits on one line, which text buttons did not.
 *
 * `data-act` is the stable hook the end-to-end tests click, so a label can be
 * re-worded or translated without touching them. `aria-label` carries the same
 * text because a tooltip alone is not reachable by keyboard or a screen reader.
 */
defineProps<{
  act: string
  icon: string
  label: string
  tone?: 'primary' | 'danger' | 'warning'
  disabled?: boolean
}>()

const emit = defineEmits<{ click: [] }>()
</script>

<template>
  <el-tooltip :content="label" placement="top" :show-after="150">
    <!-- The wrapper holds the tooltip: a disabled button swallows its own hover. -->
    <span class="row-act-wrap">
      <button
        type="button"
        class="row-act"
        :class="tone ? 'is-' + tone : ''"
        :data-act="act"
        :aria-label="label"
        :disabled="disabled"
        @click="emit('click')"
      >
        <QmsIcon :name="icon" :size="14" />
      </button>
    </span>
  </el-tooltip>
</template>
