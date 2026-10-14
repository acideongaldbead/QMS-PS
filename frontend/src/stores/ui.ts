import { defineStore } from 'pinia'

export type Density = 'comfortable' | 'compact'
export type Lang = 'zh-CN' | 'en-US'

// Same localStorage keys the approved prototype used, so a user's preferences
// carry over unchanged.
const K_DENSITY = 'qms.density'
const K_LANG = 'qms.lang'
const K_NAV = 'qms.navCollapsed'

function read<T extends string>(key: string, fallback: T): T {
  try {
    return (localStorage.getItem(key) as T) || fallback
  } catch {
    return fallback
  }
}

function write(key: string, value: string): void {
  try {
    localStorage.setItem(key, value)
  } catch {
    /* private mode: preference simply does not persist */
  }
}

export const useUiStore = defineStore('ui', {
  state: () => ({
    density: read<Density>(K_DENSITY, 'comfortable'),
    lang: read<Lang>(K_LANG, 'zh-CN'),
    navCollapsed: read<string>(K_NAV, '0') === '1'
  }),

  actions: {
    setDensity(density: Density) {
      this.density = density
      document.documentElement.dataset.density = density
      write(K_DENSITY, density)
    },

    toggleDensity() {
      this.setDensity(this.density === 'comfortable' ? 'compact' : 'comfortable')
    },

    toggleNav() {
      this.navCollapsed = !this.navCollapsed
      write(K_NAV, this.navCollapsed ? '1' : '0')
    },

    applyDensity() {
      document.documentElement.dataset.density = this.density
    }
  }
})
