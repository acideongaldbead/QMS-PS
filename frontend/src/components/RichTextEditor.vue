<script setup lang="ts">
import { onBeforeUnmount, onMounted, ref } from 'vue'
import { useI18n } from 'vue-i18n'
import type { Editor } from '@tiptap/core'

/**
 * A small rich-text editor for the announcement body.
 *
 * TipTap is imported lazily inside onMounted, the same shape WhyMindMap uses for
 * mind-elixir: the editor is only worth its weight once a screen that holds one is
 * open, and it must never reach the login or home bundle (e2e/lazy-load.mjs
 * asserts that). @tiptap/core's imperative Editor is used rather than the
 * @tiptap/vue-3 useEditor composable, whose setup() call cannot sit behind the
 * await import that keeps the package out of the entry chunk.
 *
 * The emitted HTML is sanitised again on the server before it is stored, so this
 * side only has to keep the toolbar and that whitelist in step.
 */
const props = defineProps<{ modelValue: string }>()
const emit = defineEmits<{ 'update:modelValue': [value: string] }>()

const { t } = useI18n()

const host = ref<HTMLElement | null>(null)
/** Bumped on every transaction so the toolbar's active state re-renders. */
const revision = ref(0)

// The editor instance is not reactive; the toolbar reads it through active().
let editor: Editor | null = null

function active(name: string, attrs?: Record<string, unknown>): boolean {
  void revision.value // dependency: recompute whenever the editor changes
  return editor ? editor.isActive(name, attrs) : false
}

function run(action: (chain: any) => { run: () => boolean }) {
  if (!editor) return
  action(editor.chain().focus()).run()
}

function toggleLink() {
  if (!editor) return
  const previous = (editor.getAttributes('link').href as string | undefined) ?? ''
  const url = window.prompt(t('ann.toolbar.linkPrompt'), previous || 'https://')
  if (url === null) return
  if (url.trim() === '') {
    editor.chain().focus().extendMarkRange('link').unsetLink().run()
    return
  }
  editor.chain().focus().extendMarkRange('link').setLink({ href: url.trim() }).run()
}

onMounted(async () => {
  const [{ Editor: TipTapEditor }, starterKit, underline, link] = await Promise.all([
    import('@tiptap/core'),
    import('@tiptap/starter-kit'),
    import('@tiptap/extension-underline'),
    import('@tiptap/extension-link')
  ])

  editor = new TipTapEditor({
    element: host.value as HTMLElement,
    extensions: [
      starterKit.default.configure({
        // Only the formatting an announcement needs, so the toolbar, the stored
        // HTML and the server whitelist all describe the same set.
        heading: { levels: [2, 3] },
        code: false,
        codeBlock: false,
        strike: false,
        horizontalRule: false
      }),
      underline.default,
      link.default.configure({ openOnClick: false, autolink: true })
    ],
    content: props.modelValue || '<p></p>',
    onUpdate: ({ editor: instance }) => emit('update:modelValue', instance.getHTML()),
    onTransaction: () => {
      revision.value++
    }
  })
})

onBeforeUnmount(() => {
  editor?.destroy()
  editor = null
})
</script>

<template>
  <div class="rt-editor">
    <div class="rt-toolbar" data-rt-toolbar>
      <button
        type="button"
        :class="{ 'is-on': active('bold') }"
        :title="t('ann.toolbar.bold')"
        data-rt="bold"
        @click="run((c) => c.toggleBold())"
      >
        <svg viewBox="0 0 24 24"><path d="M7 5h5.5a3.5 3.5 0 0 1 0 7H7z" /><path d="M7 12h6.5a3.5 3.5 0 0 1 0 7H7z" /></svg>
      </button>
      <button
        type="button"
        :class="{ 'is-on': active('italic') }"
        :title="t('ann.toolbar.italic')"
        data-rt="italic"
        @click="run((c) => c.toggleItalic())"
      >
        <svg viewBox="0 0 24 24"><path d="M15 5h-5M14 19H9M14.5 5 10 19" /></svg>
      </button>
      <button
        type="button"
        :class="{ 'is-on': active('underline') }"
        :title="t('ann.toolbar.underline')"
        data-rt="underline"
        @click="run((c) => c.toggleUnderline())"
      >
        <svg viewBox="0 0 24 24"><path d="M7 5v6a5 5 0 0 0 10 0V5M5 20h14" /></svg>
      </button>

      <span class="rt-sep" />

      <button
        type="button"
        class="rt-text"
        :class="{ 'is-on': active('heading', { level: 2 }) }"
        :title="t('ann.toolbar.h2')"
        data-rt="h2"
        @click="run((c) => c.toggleHeading({ level: 2 }))"
      >
        H2
      </button>
      <button
        type="button"
        class="rt-text"
        :class="{ 'is-on': active('heading', { level: 3 }) }"
        :title="t('ann.toolbar.h3')"
        data-rt="h3"
        @click="run((c) => c.toggleHeading({ level: 3 }))"
      >
        H3
      </button>

      <span class="rt-sep" />

      <button
        type="button"
        :class="{ 'is-on': active('bulletList') }"
        :title="t('ann.toolbar.bullet')"
        data-rt="bullet"
        @click="run((c) => c.toggleBulletList())"
      >
        <svg viewBox="0 0 24 24"><path d="M9 7h11M9 12h11M9 17h11M4.5 7h.01M4.5 12h.01M4.5 17h.01" /></svg>
      </button>
      <button
        type="button"
        :class="{ 'is-on': active('orderedList') }"
        :title="t('ann.toolbar.ordered')"
        data-rt="ordered"
        @click="run((c) => c.toggleOrderedList())"
      >
        <svg viewBox="0 0 24 24"><path d="M10 7h10M10 12h10M10 17h10M4.5 6h1.5v3M4.5 11.5h1.5v3.5h-1.5" /></svg>
      </button>

      <span class="rt-sep" />

      <button
        type="button"
        :class="{ 'is-on': active('blockquote') }"
        :title="t('ann.toolbar.quote')"
        data-rt="quote"
        @click="run((c) => c.toggleBlockquote())"
      >
        <svg viewBox="0 0 24 24"><path d="M6 7h4v5H8a3 3 0 0 0 0 6M14 7h4v5h-2a3 3 0 0 0 0 6" /></svg>
      </button>
      <button
        type="button"
        :class="{ 'is-on': active('link') }"
        :title="t('ann.toolbar.link')"
        data-rt="link"
        @click="toggleLink"
      >
        <svg viewBox="0 0 24 24"><path d="M9.5 14.5 14.5 9.5" /><path d="M8 12 6 14a3 3 0 0 0 4 4l2-2" /><path d="M16 12l2-2a3 3 0 0 0-4-4l-2 2" /></svg>
      </button>

      <span class="rt-sep" />

      <button type="button" :title="t('ann.toolbar.undo')" data-rt="undo" @click="run((c) => c.undo())">
        <svg viewBox="0 0 24 24"><path d="M8 7 4 11l4 4" /><path d="M4 11h9a6 6 0 0 1 0 12h-1" /></svg>
      </button>
      <button type="button" :title="t('ann.toolbar.redo')" data-rt="redo" @click="run((c) => c.redo())">
        <svg viewBox="0 0 24 24"><path d="M16 7l4 4-4 4" /><path d="M20 11h-9a6 6 0 0 0 0 12h1" /></svg>
      </button>
    </div>

    <div ref="host" class="rt-area" data-rt-area />
  </div>
</template>

<style scoped>
.rt-editor {
  width: 100%;
}

/* Keep long announcements scrollable instead of growing the dialog off-screen. */
.rt-editor .rt-area {
  max-height: 380px;
}

/* The two heading buttons carry text rather than a glyph. */
.rt-toolbar button.rt-text {
  width: auto;
  min-width: 26px;
  padding: 0 6px;
  font-size: 11px;
  font-weight: 600;
}

.rt-area :deep(.ProseMirror) {
  outline: none;
}

.rt-area :deep(p) {
  margin: 0 0 var(--sp-2);
}

.rt-area :deep(ul) {
  list-style: disc;
  padding-left: var(--sp-5);
  margin: 0 0 var(--sp-2);
}

.rt-area :deep(ol) {
  list-style: decimal;
  padding-left: var(--sp-5);
  margin: 0 0 var(--sp-2);
}

.rt-area :deep(blockquote) {
  border-left: 3px solid var(--bd-2);
  padding-left: var(--sp-3);
  color: var(--t-3);
  margin: 0 0 var(--sp-2);
}

.rt-area :deep(h2),
.rt-area :deep(h3) {
  margin: var(--sp-3) 0 var(--sp-2);
}
</style>
