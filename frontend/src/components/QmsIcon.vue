<script setup lang="ts">
import { computed } from 'vue'

// Inline stroke icons, matching the prototype's look (18-20px, 1.7 stroke).
// Static markup only -- never fed from user input.
const ICONS: Record<string, string> = {
  home: '<path d="M3 10.5 12 3l9 7.5V21H3z"/><path d="M9 21v-6h6v6"/>',
  list: '<path d="M8 6h13M8 12h13M8 18h13"/><path d="M3 6h.01M3 12h.01M3 18h.01"/>',
  plus: '<path d="M12 5v14M5 12h14"/>',
  chart: '<path d="M4 20V11M10 20V4M16 20v-6"/><path d="M2 20h20"/>',
  book: '<path d="M4 5a2 2 0 0 1 2-2h13v18H6a2 2 0 0 1-2-2z"/><path d="M8 3v18"/>',
  settings:
    '<path d="M4 21v-6M4 11V3M12 21v-9M12 8V3M20 21v-4M20 13V3"/><path d="M1 15h6M9 8h6M17 17h6"/>',
  search: '<circle cx="11" cy="11" r="7"/><path d="M21 21l-4.3-4.3"/>',
  bell: '<path d="M18 8a6 6 0 1 0-12 0c0 7-3 9-3 9h18s-3-2-3-9"/><path d="M13.7 21a2 2 0 0 1-3.4 0"/>',
  menu: '<path d="M3 6h18M3 12h18M3 18h18"/>',
  chevronLeft: '<path d="M15 18l-6-6 6-6"/>',
  globe:
    '<circle cx="12" cy="12" r="9"/><path d="M3 12h18"/><path d="M12 3a14 14 0 0 1 0 18 14 14 0 0 1 0-18"/>',
  user: '<path d="M20 21v-2a4 4 0 0 0-4-4H8a4 4 0 0 0-4 4v2"/><circle cx="12" cy="7" r="4"/>',
  logout: '<path d="M9 21H5a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h4"/><path d="M16 17l5-5-5-5"/><path d="M21 12H9"/>',
  rows: '<path d="M4 6h16M4 12h16M4 18h10"/>',
  refresh: '<path d="M21 12a9 9 0 1 1-3-6.7"/><path d="M21 4v5h-5"/>',
  eye: '<path d="M2 12s3.6-7 10-7 10 7 10 7-3.6 7-10 7-10-7-10-7z"/><circle cx="12" cy="12" r="3"/>',
  download: '<path d="M12 3v12"/><path d="M7.5 10.5 12 15l4.5-4.5"/><path d="M5 21h14"/>',
  file: '<path d="M14 3H7a2 2 0 0 0-2 2v14a2 2 0 0 0 2 2h10a2 2 0 0 0 2-2V8z"/><path d="M14 3v5h5"/>',
  // Row actions (see RowAction.vue).
  pencil: '<path d="M4 20h4L20 8a2.8 2.8 0 0 0-4-4L4 16z"/><path d="M14 6l4 4"/>',
  trash:
    '<path d="M4 7h16"/><path d="M9 7V5a1 1 0 0 1 1-1h4a1 1 0 0 1 1 1v2"/><path d="M6 7l1 12a2 2 0 0 0 2 2h6a2 2 0 0 0 2-2l1-12"/><path d="M10 11v6M14 11v6"/>',
  copy: '<rect x="9" y="9" width="12" height="12" rx="2"/><path d="M5 15H4a2 2 0 0 1-2-2V4a2 2 0 0 1 2-2h9a2 2 0 0 1 2 2v1"/>',
  transfer: '<path d="M3 8h14"/><path d="M13 4l4 4-4 4"/><path d="M21 16H7"/><path d="M11 12l-4 4 4 4"/>',
  check: '<path d="M5 13l4 4L19 7"/>',
  send: '<path d="M21 3 3 10.5l7 2.5 2.5 7z"/><path d="M21 3 10 14"/>',
  upload: '<path d="M12 16V4"/><path d="M8 8l4-4 4 4"/><path d="M5 20h14"/>',
  arrowRightFromLine: '<path d="M4 4v16"/><path d="M8 12h12"/><path d="M16 8l4 4-4 4"/>'
}

const props = defineProps<{ name: string; size?: number }>()

const inner = computed(() => ICONS[props.name] ?? '')
const px = computed(() => props.size ?? 18)
</script>

<template>
  <svg
    :width="px"
    :height="px"
    viewBox="0 0 24 24"
    fill="none"
    stroke="currentColor"
    :stroke-width="1.7"
    stroke-linecap="round"
    stroke-linejoin="round"
    aria-hidden="true"
    v-html="inner"
  />
</template>
