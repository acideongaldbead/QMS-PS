<script setup lang="ts">
import { computed, nextTick, onBeforeUnmount, onMounted, reactive, ref, watch } from 'vue'

/**
 * The fishbone (Ishikawa) editor: a structured form on the left, the diagram on
 * the right.
 *
 * The stored content is the semantic model below, not the Mermaid text -- the
 * diagram is generated from the model, so the storage survives any change of
 * rendering library, and the form keeps the input structured (and therefore
 * checkable) instead of asking a quality engineer to type diagram syntax.
 *
 * Mermaid is imported lazily: it is a large dependency and is only worth loading
 * when this tab is actually opened.
 */
export interface FishboneCause {
  text: string
  subCauses: string[]
}

export interface FishboneCategory {
  name: string
  causes: FishboneCause[]
}

export interface FishboneModel {
  effect: string
  categories: FishboneCategory[]
}

const props = withDefaults(
  defineProps<{
    /** The stored model as JSON, or null when nothing has been saved yet. */
    modelValue?: string | null
    /** Seeds the effect when there is nothing stored. */
    defaultEffect?: string
    readonly?: boolean
  }>(),
  { modelValue: null, defaultEffect: '', readonly: false }
)

/** The classic 6M, in the wording the quality team uses. */
const SIX_M = ['人', '机', '料', '法', '环', '测']

const model = reactive<FishboneModel>({ effect: '', categories: [] })

const container = ref<HTMLElement | null>(null)
const rendering = ref(false)
const renderError = ref('')
const mermaidReady = ref(false)
let mermaidApi: any = null
let renderSeq = 0
let debounceTimer: ReturnType<typeof setTimeout> | null = null

function emptyModel(): FishboneModel {
  return {
    effect: props.defaultEffect || '失效现象',
    categories: SIX_M.map((name) => ({ name, causes: [] }))
  }
}

function loadFrom(value: string | null) {
  const fallback = emptyModel()
  if (!value || !value.trim()) {
    Object.assign(model, fallback)
    return
  }
  try {
    const parsed = JSON.parse(value) as FishboneModel
    model.effect = parsed.effect ?? fallback.effect
    model.categories =
      Array.isArray(parsed.categories) && parsed.categories.length
        ? parsed.categories.map((c) => ({
            name: c.name ?? '',
            causes: (c.causes ?? []).map((k) => ({
              text: k.text ?? '',
              subCauses: k.subCauses ?? []
            }))
          }))
        : fallback.categories
  } catch {
    Object.assign(model, fallback)
  }
}

/**
 * Builds the diagram source. Mermaid reads it as: the first line is the effect
 * (the fish head), and every following line's indentation decides its level, so
 * category -> cause -> sub-cause is 2/4/6 spaces.
 *
 * Text is trimmed and stripped of newlines: leading whitespace would be read as
 * indentation and a newline would split one cause into two lines.
 */
function toMermaid(m: FishboneModel): string {
  const clean = (text: string) => (text ?? '').replace(/[\r\n]+/g, ' ').trim()

  const lines: string[] = ['ishikawa', clean(m.effect) || '失效现象']
  for (const category of m.categories) {
    const name = clean(category.name)
    if (!name) continue
    lines.push('  ' + name)
    for (const cause of category.causes) {
      const causeText = clean(cause.text)
      if (!causeText) continue
      lines.push('    ' + causeText)
      for (const sub of cause.subCauses) {
        const subText = clean(sub)
        if (subText) lines.push('      ' + subText)
      }
    }
  }
  return lines.join('\n')
}

const diagramSource = computed(() => toMermaid(model))

async function render() {
  if (!mermaidApi || !container.value) return
  if (rendering.value) return
  rendering.value = true
  const id = 'qms-fishbone-' + ++renderSeq
  try {
    const { svg } = await mermaidApi.render(id, diagramSource.value)
    if (container.value) container.value.innerHTML = svg
    renderError.value = ''
  } catch (e) {
    renderError.value = e instanceof Error ? e.message : String(e)
  } finally {
    rendering.value = false
  }
}

/** Redraws shortly after the last edit, so the diagram tracks typing without lag. */
function scheduleRender() {
  if (debounceTimer) clearTimeout(debounceTimer)
  debounceTimer = setTimeout(() => void render(), 400)
}

watch(diagramSource, scheduleRender)

onMounted(async () => {
  loadFrom(props.modelValue)
  try {
    // A dynamic import, so Mermaid and its diagram chunks are fetched only when
    // this editor is opened -- never on the complaint page or the entry bundle.
    // Mermaid then pulls just the diagram it is asked to render.
    const [{ default: mermaid }] = await Promise.all([import('mermaid')])
    mermaid.initialize({
      startOnLoad: false,
      // strict sanitises node labels; the causes are free text typed by users, so
      // the diagram must not be able to inject markup.
      securityLevel: 'strict',
      theme: 'base',
      fontFamily: 'var(--font-sans), "Microsoft YaHei", sans-serif',
      themeVariables: {
        primaryColor: '#E9F5F1',
        primaryTextColor: '#2A3441',
        primaryBorderColor: '#0E7C66',
        lineColor: '#6E7C90',
        secondaryColor: '#F6F8FA',
        tertiaryColor: '#FFFFFF',
        fontSize: '13px'
      }
    })
    mermaidApi = mermaid
    mermaidReady.value = true
    await nextTick()
    await render()
  } catch (e) {
    renderError.value = '鱼骨图渲染库加载失败：' + (e instanceof Error ? e.message : String(e))
  }
})

onBeforeUnmount(() => {
  if (debounceTimer) clearTimeout(debounceTimer)
})

// ---------------------------------------------------------------- form actions

function addCategory() {
  model.categories.push({ name: '新分类', causes: [] })
}

function removeCategory(index: number) {
  model.categories.splice(index, 1)
}

function addCause(category: FishboneCategory) {
  category.causes.push({ text: '', subCauses: [] })
}

function removeCause(category: FishboneCategory, index: number) {
  category.causes.splice(index, 1)
}

function addSubCause(cause: FishboneCause) {
  cause.subCauses.push('')
}

function removeSubCause(cause: FishboneCause, index: number) {
  cause.subCauses.splice(index, 1)
}

/** The model as the JSON that gets stored; called by the parent on save. */
function getData(): string {
  return JSON.stringify(model)
}

defineExpose({ getData, render })
</script>

<template>
  <div class="fb-wrap">
    <el-row :gutter="16">
      <el-col :span="11">
        <div class="fb-form">
          <el-form label-width="90px" size="small">
            <el-form-item label="失效现象">
              <el-input v-model="model.effect" placeholder="鱼头：本次要分析的失效现象" :disabled="readonly" />
            </el-form-item>
          </el-form>

          <div class="fb-cat-list">
            <el-card v-for="(category, ci) in model.categories" :key="ci" shadow="never" class="fb-cat">
              <template #header>
                <div class="row-between">
                  <el-input
                    v-model="category.name"
                    size="small"
                    class="fb-cat-name"
                    :disabled="readonly"
                  />
                  <el-button v-if="!readonly" link type="danger" @click="removeCategory(ci)">移除分类</el-button>
                </div>
              </template>

              <div v-for="(cause, ki) in category.causes" :key="ki" class="fb-cause">
                <div class="fb-cause-row">
                  <el-input
                    v-model="cause.text"
                    size="small"
                    placeholder="原因"
                    :disabled="readonly"
                  />
                  <el-button v-if="!readonly" link type="primary" @click="addSubCause(cause)">+ 子原因</el-button>
                  <el-button v-if="!readonly" link type="danger" @click="removeCause(category, ki)">移除</el-button>
                </div>
                <div v-for="(_, si) in cause.subCauses" :key="si" class="fb-sub-row">
                  <el-input
                    v-model="cause.subCauses[si]"
                    size="small"
                    placeholder="子原因"
                    :disabled="readonly"
                  />
                  <el-button v-if="!readonly" link type="danger" @click="removeSubCause(cause, si)">移除</el-button>
                </div>
              </div>

              <el-button v-if="!readonly" size="small" link type="primary" @click="addCause(category)">
                + 添加原因
              </el-button>
            </el-card>
          </div>

          <el-button v-if="!readonly" size="small" plain class="mt-2" @click="addCategory">+ 添加分类</el-button>
        </div>
      </el-col>

      <el-col :span="13">
        <div class="fb-preview">
          <div class="row-between mb-2">
            <span class="fs-12 t-3">实时预览</span>
            <el-button size="small" link :disabled="!mermaidReady" @click="render">刷新</el-button>
          </div>
          <div ref="container" class="fb-svg" v-loading="rendering" />
          <el-alert
            v-if="renderError"
            class="mt-2"
            type="warning"
            :closable="false"
            show-icon
            :title="renderError"
          />
        </div>
      </el-col>
    </el-row>
  </div>
</template>

<style scoped>
.fb-wrap {
  max-height: 640px;
  overflow-y: auto;
}
.fb-cat {
  margin-bottom: 10px;
}
.fb-cat :deep(.el-card__header) {
  padding: 8px 12px;
  background: var(--n-25);
}
.fb-cat-name {
  width: 160px;
}
.fb-cause {
  margin-bottom: 10px;
}
.fb-cause-row {
  display: flex;
  align-items: center;
  gap: 8px;
}
.fb-sub-row {
  display: flex;
  align-items: center;
  gap: 8px;
  margin-top: 6px;
  margin-left: 24px;
}
.fb-preview {
  position: sticky;
  top: 0;
}
.fb-svg {
  min-height: 460px;
  border: 1px solid var(--bd-1);
  border-radius: var(--r-2);
  background: var(--bg-surface);
  padding: 12px;
  overflow: auto;
}
.fb-svg :deep(svg) {
  max-width: 100%;
  height: auto;
}
</style>
