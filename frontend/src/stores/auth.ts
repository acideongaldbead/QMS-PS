import { defineStore } from 'pinia'
import http, { TOKEN_KEY } from '@/api/http'

export interface CurrentUser {
  employeeId: string
  name: string
  nameEn?: string
  email?: string
  deptL1?: string
  deptL2?: string
  title?: string
  roles: string[]
  permissions: string[]
}

export const useAuthStore = defineStore('auth', {
  state: () => ({
    user: null as CurrentUser | null,
    loaded: false
  }),

  getters: {
    isAuthenticated: (s) => !!s.user,
    /** Mirrors the prototype's QMSShell.can(action). */
    can: (s) => (permission: string) => !!s.user?.permissions?.includes(permission),
    hasAnyRole: (s) => (roles: string[]) => roles.some((r) => s.user?.roles?.includes(r))
  },

  actions: {
    async login(username: string, password: string) {
      const { data } = await http.post<{ accessToken: string; refreshToken: string }>(
        '/auth/login',
        { username, password }
      )
      localStorage.setItem(TOKEN_KEY, data.accessToken)
      await this.fetchMe()
    },

    async fetchMe() {
      const { data } = await http.get<CurrentUser>('/auth/me')
      this.user = data
      this.loaded = true
    },

    /** Restore the session on a hard refresh, if a token is present. */
    async restore() {
      if (this.loaded) return
      if (!localStorage.getItem(TOKEN_KEY)) {
        this.loaded = true
        return
      }
      try {
        await this.fetchMe()
      } catch {
        localStorage.removeItem(TOKEN_KEY)
        this.user = null
        this.loaded = true
      }
    },

    logout() {
      localStorage.removeItem(TOKEN_KEY)
      this.user = null
      this.loaded = true
    }
  }
})
