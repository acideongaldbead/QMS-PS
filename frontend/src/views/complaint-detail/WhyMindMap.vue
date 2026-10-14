<script setup lang="ts">
import { onBeforeUnmount, onMounted, ref, shallowRef } from 'vue'
import { ElMessage } from 'element-plus'

/**
 * The 3x5Why editor as a mind map (mind-elixir).
 *
 * The business structure is a tree -- one question with several reasons, and each
 * reason can carry the next question -- which is exactly what a mind map models:
 * the root is the failure symptom, and every deeper node is alternately a "why"
 * (question) or an "answer" (reason). Adding a child node is the 「+」 the
 * requirement describes, and the library supplies drag, zoom, undo and image
 * export on top.
 *
 * The library is imported lazily: it is only worth its weight when this editor is
 * actually opened, not on the detail page as a whole.
 */
const props = withDefaults(
  defineProps<{
    /** mind-elixir's own serialised shape, as stored in why_analysis.content_json. */
    modelValue?: string | null
    /** Used to seed a diagram that has never been saved. */
    rootTopic: string
    readonly?: boolean
  }>(),
  { modelValue: null, readonly: false }
)

const host = ref<HTMLElement | null>(null)
const loading = ref(true)
const loadError = ref('')
// shallowRef: the instance is a large class whose internals must not be made
// reactive, or Vue would walk the whole DOM tree it owns.
const mind = shallowRef<any>(null)

/** Seeds a fresh diagram: the symptom, plus one empty reason to start from. */
function defaultData(MindElixir: any): string {
  const data = MindElixir.new(props.rootTopic || '失效现象')
  const root = data.nodeData
  root.children = [{ id: 'ans-1', topic: '原因 1', children: [], direction: 1 }]
  return JSON.stringify(data)
}

/**
 * Themes the map with the app's own tokens by starting from the library's theme
 * and overriding the colours, so the keys are guaranteed to be the ones it reads.
 */
function qmsTheme(MindElixir: any) {
  const theme = JSON.parse(JSON.stringify(MindElixir.THEME))
  theme.name = 'qms'
  theme.palette = ['#0E7C66', '#389E86', '#6BBBA6', '#9FD3C5', '#CBE8DF']
  Object.assign(theme.cssVar, {
    '--main-color': '#0E7C66',
    '--main-bgcolor': '#FFFFFF',
    '--color': '#2A3441',
    '--bgcolor': '#F6F8FA',
    '--selected': '#E9F5F1',
    '--root-color': '#FFFFFF',
    '--root-bgcolor': '#0E7C66',
    '--topic-padding': '6px'
  })
  return theme
}

onMounted(async () => {
  if (!host.value) return
  try {
    const [{ default: MindElixir }] = await Promise.all([
      import('mind-elixir'),
      import('mind-elixir/style')
    ])

    const raw = props.modelValue && props.modelValue.trim() ? props.modelValue : defaultData(MindElixir)
    const data = JSON.parse(raw)

    mind.value = new MindElixir({
      el: host.value,
      direction: MindElixir.RIGHT,
      editable: !props.readonly,
      // The built-in toolbar and context menu are the discoverable path to
      // "add a child" / "add a sibling", which is the interaction the business
      // asked for.
      toolBar: !props.readonly,
      contextMenu: !props.readonly,
      keypress: !props.readonly,
      allowUndo: true,
      overflowHidden: false,
      theme: qmsTheme(MindElixir)
    })
    mind.value.init(data)
    mind.value.scaleFit()
  } catch (e) {
    loadError.value = e instanceof Error ? e.message : String(e)
  } finally {
    loading.value = false
  }
})

onBeforeUnmount(() => {
  // The library attaches document-level listeners (wheel, keydown); destroy()
  // removes them, otherwise leaving the tab leaves them behind.
  try {
    mind.value?.destroy?.()
  } catch {
    /* already gone */
  }
  mind.value = null
})

/** Adds a child to the selected node: one more reason, or one more why level. */
async function addChild() {
  if (!mind.value) return
  const current = mind.value.currentNode
  if (!current) {
    ElMessage.warning('请先点选一个节点，再添加下一层')
    return
  }
  await mind.value.addChild()
}

/** Adds a sibling to the selected node: another reason for the same question. */
async function addSibling() {
  if (!mind.value) return
  const current = mind.value.currentNode
  if (!current) {
    ElMessage.warning('请先点选一个节点，再添加同级原因')
    return
  }
  await mind.value.insertSibling('after')
}

async function removeSelected() {
  if (!mind.value) return
  const current = mind.value.currentNode
  if (!current) {
    ElMessage.warning('请先点选要删除的节点')
    return
  }
  await mind.value.removeNodes([current])
}

function fit() {
  mind.value?.scaleFit()
}

function exportImage() {
  if (!mind.value) return
  mind.value.exportPng().then((blob: Blob | null) => {
    if (!blob) {
      ElMessage.error('导出图片失败')
      return
    }
    const url = window.URL.createObjectURL(blob)
    const link = document.createElement('a')
    link.href = url
    link.download = '3x5Why.png'
    document.body.appendChild(link)
    link.click()
    document.body.removeChild(link)
    window.URL.revokeObjectURL(url)
  })
}

/**
 * The current diagram as the JSON that gets stored. Called by the parent when the
 * user saves, rather than listening for every edit, so nothing is written until
 * the user asks for it.
 */
function getData(): string {
  if (!mind.value) {
    return props.modelValue || ''
  }
  return mind.value.getDataString()
}

defineExpose({ getData, addChild, addSibling, removeSelected, fit, exportImage })
</script>

<template>
  <div class="mind-wrap">
    <div v-if="!readonly" class="mind-toolbar">
      <el-button size="small" type="primary" plain @click="addChild">+ 下一层（子节点）</el-button>
      <el-button size="small" @click="addSibling">+ 同级原因</el-button>
      <el-button size="small" type="danger" plain @click="removeSelected">删除所选</el-button>
      <div class="spacer" />
      <el-button size="small" link @click="fit">适应画布</el-button>
      <el-button size="small" link @click="exportImage">导出图片</el-button>
    </div>
    <div class="mind-hint fs-12 t-3">
      双击节点改文字；拖拽可调整层级；滚轮缩放；Tab 加子节点、Enter 加同级（可撤销）。
    </div>
    <div ref="host" class="mind-host" />
    <el-skeleton v-if="loading" :rows="5" animated class="mind-loading" />
    <el-alert v-if="loadError" type="error" :closable="false" show-icon :title="'思维导图加载失败：' + loadError" />
  </div>
</template>

<style scoped>
.mind-wrap {
  display: flex;
  flex-direction: column;
  gap: 6px;
}
.mind-toolbar {
  display: flex;
  align-items: center;
  gap: 8px;
}
.spacer {
  flex: 1 1 auto;
}
.mind-hint {
  line-height: 1.5;
}
.mind-host {
  height: 520px;
  border: 1px solid var(--bd-1);
  border-radius: var(--r-2);
  background: var(--bg-surface);
  overflow: hidden;
}
.mind-loading {
  margin-top: -520px;
  pointer-events: none;
}
</style>
