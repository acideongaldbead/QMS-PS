import axios, { type AxiosInstance, type AxiosError } from 'axios'

export const TOKEN_KEY = 'qms.token'

const http: AxiosInstance = axios.create({
  baseURL: '/api',
  timeout: 30000
})

http.interceptors.request.use((config) => {
  const token = localStorage.getItem(TOKEN_KEY)
  if (token) {
    config.headers.Authorization = `Bearer ${token}`
  }
  return config
})

http.interceptors.response.use(
  (res) => res,
  (error: AxiosError) => {
    if (error.response?.status === 401) {
      localStorage.removeItem(TOKEN_KEY)
      const here = window.location.hash || ''
      if (!here.startsWith('#/login')) {
        window.location.hash = '#/login'
      }
    }
    return Promise.reject(error)
  }
)

/** Pull a readable message out of a Spring Boot error body. */
export function errorMessage(error: unknown): string {
  const e = error as AxiosError<{ message?: string; error?: string }>
  return e?.response?.data?.message || e?.response?.data?.error || e?.message || '请求失败'
}

export default http
