/// <reference types="vite/client" />

declare module '*.vue' {
  import type { DefineComponent } from 'vue'
  const component: DefineComponent<{}, {}, any>
  export default component
}

// The package exposes its stylesheet at this sub-path without shipping types.
declare module 'mind-elixir/style'
