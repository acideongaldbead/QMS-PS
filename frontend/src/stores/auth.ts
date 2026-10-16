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
  /**
   * Set while a forced password change is pending: the account still holds a seed
   * password, or an administrator reset it. The server refuses every other API
   * until it is cleared, so the router steers straight to the change screen
   * (requirement 3.12).
   */
  mustChangePwd?: boolean
}

export const useAuthStore = defineStore('auth', {
  state: () => ({
    user: null as CurrentUser | null,
    loaded: false
  }),

  getters: {
    isAuthenticated: (s) => !!s.user,
    mustChangePwd: (s) => !!s.user?.mustChangePwd,
    /** Mirrors the prototype's QMSShell.can(action). */
    can: (s) => (permission: string) => !!s.user?.permissions?.includes(permission),
    hasAnyRole: (s) => (roles: string[]) => roles.some((r) => s.user?.roles?.includes(r))
  },

  actions: {
    async login(username: string, password: string) {
      // The response carries the token only; there is no refresh token, the access
      // token is the whole session.
      const { data } = await http.post<{ accessToken: string }>('/auth/login', {
        username,
        password
      })
      localStorage.setItem(TOKEN_KEY, data.accessToken)
      await this.fetchMe()
    },

    async fetchMe() {
      const { data } = await http.get<CurrentUser>('/auth/me')
      this.user = data
      this.loaded = true
    },

    /**
     * Changes the caller's own password, then re-reads the profile so a cleared
     * forced-change flag takes effect on this session at once.
     */
    async changePassword(oldPassword: string, newPassword: string) {
      await http.post('/auth/change-password', { oldPassword, newPassword })
      await this.fetchMe()
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
