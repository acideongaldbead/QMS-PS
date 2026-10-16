import http from './http'

/**
 * The RBAC administration API (requirement 3.12): users, roles and the permission
 * matrix.
 *
 * Types are written by hand, like every other api/*.ts: there is no generated
 * client, so a change to the Java record has to be mirrored here.
 */

/** One employee as the user screen shows them. */
export interface AdminUser {
  employeeId: string
  name: string
  nameEn?: string | null
  deptL1?: string | null
  deptL2?: string | null
  jobTitle?: string | null
  email?: string | null
  /** Null when the employee has no account yet -- roles can still be assigned. */
  username?: string | null
  accountActive?: boolean | null
  locked: boolean
  mustChangePwd?: boolean | null
  roleCodes: string[]
}

export interface AdminRole {
  roleId: number
  roleCode: string
  roleName: string
  roleNameEn?: string | null
  /** PRESET (read-only) or CUSTOM. */
  roleType: string
  isActive: boolean
  userCount: number
  permissionIds: number[]
}

export interface AdminPermission {
  permissionId: number
  permissionCode: string
  permissionName: string
  permissionNameEn?: string | null
  /** SYSTEM | MODULE | BUTTON | ROW */
  permissionLevel: string
  moduleCode?: string | null
}

/** Create and rename share one shape; the role id travels in the path. */
export interface RoleSaveRequest {
  roleName: string
  roleNameEn?: string | null
  permissionIds?: number[]
}

export const adminApi = {
  // ---- users -------------------------------------------------------------
  users: () => http.get<AdminUser[]>('/admin/users').then((r) => r.data),

  assignRoles: (employeeId: string, roleCodes: string[]) =>
    http.put(`/admin/users/${employeeId}/roles`, { roleCodes }).then(() => undefined),

  activateAccount: (employeeId: string) =>
    http.post(`/admin/users/${employeeId}/account/activate`).then(() => undefined),

  deactivateAccount: (employeeId: string) =>
    http.post(`/admin/users/${employeeId}/account/deactivate`).then(() => undefined),

  resetPassword: (employeeId: string, newPassword: string) =>
    http.post(`/admin/users/${employeeId}/password/reset`, { newPassword }).then(() => undefined),

  unlock: (employeeId: string) => http.post(`/admin/users/${employeeId}/unlock`).then(() => undefined),

  // ---- roles -------------------------------------------------------------
  roles: () => http.get<AdminRole[]>('/admin/roles').then((r) => r.data),

  createRole: (body: RoleSaveRequest) =>
    http.post<AdminRole>('/admin/roles', body).then((r) => r.data),

  renameRole: (roleId: number, body: RoleSaveRequest) =>
    http.put<AdminRole>(`/admin/roles/${roleId}`, body).then((r) => r.data),

  deleteRole: (roleId: number) => http.delete(`/admin/roles/${roleId}`).then(() => undefined),

  /** The name is optional: the server derives "<source>-副本" when it is omitted. */
  copyRole: (roleId: number, roleName?: string) =>
    http.post<AdminRole>(`/admin/roles/${roleId}/copy`, { roleName: roleName ?? null }).then((r) => r.data),

  activateRole: (roleId: number) =>
    http.post<AdminRole>(`/admin/roles/${roleId}/activate`).then((r) => r.data),

  deactivateRole: (roleId: number) =>
    http.post<AdminRole>(`/admin/roles/${roleId}/deactivate`).then((r) => r.data),

  setRolePermissions: (roleId: number, permissionIds: number[]) =>
    http.put<AdminRole>(`/admin/roles/${roleId}/permissions`, { permissionIds }).then((r) => r.data),

  // ---- permissions -------------------------------------------------------
  permissions: () => http.get<AdminPermission[]>('/admin/permissions').then((r) => r.data),

  exportMatrix: () =>
    http.get('/admin/permissions/matrix/export', { responseType: 'blob' }).then((r) => r.data as Blob)
}
