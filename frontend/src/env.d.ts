/// <reference types="vite/client" />

declare module '*.vue' {
  import type { DefineComponent } from 'vue'
  const component: DefineComponent<{}, {}, any>
  export default component
}

// The package exposes its stylesheet at this sub-path without shipping types.
declare module 'mind-elixir/style'

// pptx-preview ships neither type declarations nor a "types"/"exports" field.
declare module 'pptx-preview' {
  export function init(
    element: HTMLElement,
    options?: { width?: number; height?: number }
  ): { preview(data: ArrayBuffer | Blob | Uint8Array): Promise<void> | void }
}
