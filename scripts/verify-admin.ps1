<#
  verify-admin.ps1
  Acceptance for requirement 3.12 - the user / role / permission screens.

  Covers: the permission boundary and its audit trail; the user list; role CRUD,
  copy, enable/disable and the read-only preset roles; the permission matrix and
  its export; password reset with the forced change; account enable/disable;
  login unlock; the guard rails that stop the last administrator disappearing.

  The two assertions this task lives or dies on:
    - a permission change reaches an ALREADY ISSUED token on its next request;
    - an account flagged for a forced password change is confined to the two
      endpoints it needs.

  Pure ASCII.

  Usage (single line):
    & "C:\Users\Vivien.ma\Documents\Vivien\ps\qms-app\scripts\verify-admin.ps1"
  Optional:
    -BaseUrl http://localhost:8080   -Password Qms@2026   -KeepData
#>
[CmdletBinding()]
param(
    [string] $BaseUrl = 'http://localhost:8080',
    [string] $Password = 'Qms@2026',
    # Keep the roles and account changes this script made, for inspection.
    [switch] $KeepData
)

$ErrorActionPreference = 'Continue'

$cfgPath = Join-Path $PSScriptRoot '_paths.json'
$cfg = [System.IO.File]::ReadAllText($cfgPath) | ConvertFrom-Json
if (-not (Test-Path $cfg.outDir)) { New-Item -ItemType Directory -Path $cfg.outDir -Force | Out-Null }

$pass = 0
$fail = 0
$lines = New-Object System.Collections.Generic.List[string]
function Check([string] $name, [bool] $ok, [string] $detail) {
    if ($ok) { $script:pass++; $lines.Add(('  PASS  {0}' -f $name)) }
    else     { $script:fail++; $lines.Add(('  FAIL  {0}  -> {1}' -f $name, $detail)) }
}

function Login([string] $user, [string] $pwd) {
    $body = @{ username = $user; password = $pwd } | ConvertTo-Json
    return Invoke-RestMethod -Uri ($BaseUrl + '/api/auth/login') -Method Post `
        -ContentType 'application/json' -Body $body -TimeoutSec 20
}

function Try-Login([string] $user, [string] $pwd) {
    try {
        $body = @{ username = $user; password = $pwd } | ConvertTo-Json
        return Invoke-RestMethod -Uri ($BaseUrl + '/api/auth/login') -Method Post `
            -ContentType 'application/json' -Body $body -TimeoutSec 20
    } catch {
        return $null
    }
}

function Invoke-Api([string] $method, [string] $path, [string] $token, $payload) {
    $headers = @{}
    if ($token) { $headers['Authorization'] = 'Bearer ' + $token }
    $reqArgs = @{ Uri = $BaseUrl + $path; Method = $method; Headers = $headers; TimeoutSec = 30; UseBasicParsing = $true }
    if ($null -ne $payload) {
        $reqArgs['ContentType'] = 'application/json; charset=utf-8'
        $reqArgs['Body'] = [System.Text.Encoding]::UTF8.GetBytes(($payload | ConvertTo-Json -Depth 12))
    }
    try {
        # Invoke-WebRequest, not Invoke-RestMethod: the latter hides the status code,
        # which would turn every 'expects 201/204' assertion into a silent failure.
        $response = Invoke-WebRequest @reqArgs
        $body = $null
        if ($response.Content -is [byte[]]) {
            $body = $response.Content
        } elseif ($response.Content) {
            try { $body = $response.Content | ConvertFrom-Json } catch { $body = $response.Content }
        }
        return @{ status = [int]$response.StatusCode; body = $body }
    } catch {
        $status = 0
        $message = $_.Exception.Message
        try {
            $status = [int]$_.Exception.Response.StatusCode
            $reader = New-Object System.IO.StreamReader($_.Exception.Response.GetResponseStream())
            $text = $reader.ReadToEnd()
            $reader.Close()
            $parsed = $text | ConvertFrom-Json
            if ($parsed.message) { $message = $parsed.message }
        } catch { }
        return @{ status = $status; body = $null; message = $message }
    }
}

function Me([string] $token) {
    return (Invoke-Api 'GET' '/api/auth/me' $token $null).body
}

# --- database access, for the audit and account assertions -------------------
$envFile = Join-Path $cfg.root 'config\.env'
$vars = @{}
foreach ($line in [System.IO.File]::ReadAllLines($envFile)) {
    $t = $line.Trim()
    if ($t -eq '' -or $t.StartsWith('#')) { continue }
    $i = $t.IndexOf('=')
    if ($i -lt 1) { continue }
    $vars[$t.Substring(0, $i).Trim()] = $t.Substring($i + 1).Trim()
}
$dbMatch = [regex]::Match($vars['QMS_DB_URL'], 'jdbc:postgresql://([^:/]+)(?::(\d+))?/([^?]+)')
$dbHost = $dbMatch.Groups[1].Value
$dbPort = $dbMatch.Groups[2].Value
$dbName = $dbMatch.Groups[3].Value
$dbUser = $vars['QMS_DB_USER']
$env:PGCLIENTENCODING = 'UTF8'
$env:PGPASSWORD = $vars['QMS_DB_PASSWORD']
$psql = Join-Path $cfg.pgBin 'psql.exe'

function Q([string] $sql) {
    return ((& $psql -h $dbHost -p $dbPort -U $dbUser -d $dbName -t -A -c $sql) -join '').Trim()
}

$lines.Add('verify-admin  ->  ' + $BaseUrl)
$lines.Add('')

# ===========================================================================
# 0. Who we act on, captured before anything changes
# ===========================================================================
$admin = Login 'ying.zhou' $Password
Check 'administrator logged in' ($null -ne $admin -and $admin.accessToken) 'login failed'
if (-not $admin.accessToken) {
    $lines | ForEach-Object { [Console]::Out.WriteLine($_) }
    exit 1
}
$adminToken = $admin.accessToken
$adminEmployeeId = $admin.user.employeeId
Check 'the administrator id is known' ($adminEmployeeId -ne '') ('id=' + $adminEmployeeId)

# The engineer whose session proves a permission change lands on an old token.
# Employee id is looked up, not assumed: the id and the username are unrelated.
$qe = Login 'siyuan.li' $Password
Check 'quality engineer logged in' ($null -ne $qe -and $qe.accessToken) 'login failed'
$qeToken = $qe.accessToken

# An account nobody else's verification depends on, for the password and lock work.
$subject = Q "select employee_id || '|' || username || '|' || password_hash from qms.user_account where username <> 'siyuan.li' and is_deleted = false and employee_id in ('U02','U04','U06','U07','U09') order by employee_id limit 1;"
$subjectParts = $subject.Split('|')
$subjectId = $subjectParts[0]
$subjectUser = $subjectParts[1]
$subjectHash = $subjectParts[2]
Check 'found a spare account to exercise' ($subjectId -ne '' -and $subjectUser -ne '') ('row=' + $subject)

$users = @((Invoke-Api 'GET' '/api/admin/users' $adminToken $null).body)
$adminRoleId = 0
$roles = @((Invoke-Api 'GET' '/api/admin/roles' $adminToken $null).body)
foreach ($r in $roles) { if ($r.roleCode -eq 'ROLE_ADMINISTRATOR') { $adminRoleId = $r.roleId } }
$adminRolePermissions = 0
foreach ($r in $roles) { if ($r.roleCode -eq 'ROLE_ADMINISTRATOR') { $adminRolePermissions = @($r.permissionIds).Count } }

$qeEmployeeId = ''
$qeRoles = @()
foreach ($u in $users) {
    if ($u.username -eq 'siyuan.li') { $qeEmployeeId = $u.employeeId; $qeRoles = @($u.roleCodes) }
}
Check 'the engineer is identified in the user list' ($qeEmployeeId -ne '' -and $qeRoles.Count -ge 1) ('id=' + $qeEmployeeId)

# ===========================================================================
# 1. Permission boundary, and the refusal audit
# ===========================================================================
$anon = Invoke-Api 'GET' '/api/admin/users' '' $null
Check 'the user list requires a login (401)' ($anon.status -eq 401) ('status=' + $anon.status)

$refused = Invoke-Api 'GET' '/api/admin/users' $qeToken $null
Check 'a quality engineer is refused the user list (403)' ($refused.status -eq 403) ('status=' + $refused.status)

$deniedAudit = Q ("select count(*) from qms.audit_log where action_type='ACCESS_DENIED' and operator_id='" + $qeEmployeeId + "' and after_value like '%/api/admin/users%';")
Check 'the refused attempt left an audit row (PS-113 AC3)' ([int]$deniedAudit -ge 1) ('rows=' + $deniedAudit)

$refusedWrite = Invoke-Api 'POST' '/api/admin/roles' $qeToken @{ roleName = 'VERIFYADMIN-NOPE' }
Check 'a quality engineer cannot create a role (403)' ($refusedWrite.status -eq 403) ('status=' + $refusedWrite.status)

# ===========================================================================
# 2. The user list
# ===========================================================================
Check 'the user list loads' ($users.Count -ge 9) ('rows=' + $users.Count)
$adminRow = @($users | Where-Object { $_.employeeId -eq 'U08' })[0]
Check 'the administrator row carries its role' (@($adminRow.roleCodes) -contains 'ROLE_ADMINISTRATOR') (@($adminRow.roleCodes) -join ',')
Check 'a user row exposes the account state' ($null -ne $adminRow.username -and $adminRow.accountActive -eq $true) ('username=' + $adminRow.username)

# ===========================================================================
# 3. Role management
# ===========================================================================
$permissions = @((Invoke-Api 'GET' '/api/admin/permissions' $adminToken $null).body)
Check 'the permission vocabulary loads (26)' ($permissions.Count -eq 26) ('count=' + $permissions.Count)

$sendId = 0
$rbacId = 0
foreach ($p in $permissions) {
    if ($p.permissionCode -eq 'report:send') { $sendId = $p.permissionId }
    if ($p.permissionCode -eq 'rbac:manage') { $rbacId = $p.permissionId }
}
Check 'the matrix knows report:send and rbac:manage' ($sendId -gt 0 -and $rbacId -gt 0) ('send=' + $sendId + ' rbac=' + $rbacId)

# 3a. preset roles are read-only
$presetRename = Invoke-Api 'PUT' ('/api/admin/roles/' + $adminRoleId) $adminToken @{ roleName = 'VERIFYADMIN-RENAMED' }
Check 'a preset role cannot be renamed (409)' ($presetRename.status -eq 409) ('status=' + $presetRename.status)

$presetDelete = Invoke-Api 'DELETE' ('/api/admin/roles/' + $adminRoleId) $adminToken $null
Check 'a preset role cannot be deleted (409)' ($presetDelete.status -eq 409) ('status=' + $presetDelete.status)

$presetOff = Invoke-Api 'POST' ('/api/admin/roles/' + $adminRoleId + '/deactivate') $adminToken $null
Check 'a preset role cannot be disabled (409)' ($presetOff.status -eq 409) ('status=' + $presetOff.status)

$presetPerms = Invoke-Api 'PUT' ('/api/admin/roles/' + $adminRoleId + '/permissions') $adminToken @{ permissionIds = @($sendId) }
Check 'a preset role cannot have its permissions edited (409)' ($presetPerms.status -eq 409) ('status=' + $presetPerms.status)

# 3b. create, and the live permissions that come with it
$created = Invoke-Api 'POST' '/api/admin/roles' $adminToken @{ roleName = 'VERIFYADMIN-LIVE'; roleNameEn = 'Verify live'; permissionIds = @($sendId, $rbacId) }
Check 'a custom role is created (201)' ($created.status -eq 201) ('status=' + $created.status)
$liveRoleId = $created.body.roleId
$liveRoleCode = $created.body.roleCode
Check 'the new role is a CUSTOM one' ($created.body.roleType -eq 'CUSTOM') ('type=' + $created.body.roleType)
Check 'the generated role code is stable' ($liveRoleCode -like 'ROLE_CUSTOM_*') ('code=' + $liveRoleCode)
Check 'the new role carries the chosen permissions' (@($created.body.permissionIds).Count -eq 2) ('ids=' + (@($created.body.permissionIds) -join ','))

$duplicate = Invoke-Api 'POST' '/api/admin/roles' $adminToken @{ roleName = 'VERIFYADMIN-LIVE' }
Check 'a duplicate role name is refused (409)' ($duplicate.status -eq 409) ('status=' + $duplicate.status)

$badPerm = Invoke-Api 'POST' '/api/admin/roles' $adminToken @{ roleName = 'VERIFYADMIN-BADPERM'; permissionIds = @(999999) }
Check 'an unknown permission is refused (400)' ($badPerm.status -eq 400) ('status=' + $badPerm.status)

# 3c. copy a preset role
$copied = Invoke-Api 'POST' ('/api/admin/roles/' + $adminRoleId + '/copy') $adminToken @{ roleName = 'VERIFYADMIN-COPY' }
Check 'a preset role can be copied (201)' ($copied.status -eq 201) ('status=' + $copied.status)
Check 'the copy is a CUSTOM role' ($copied.body.roleType -eq 'CUSTOM') ('type=' + $copied.body.roleType)
Check 'the copy inherits every permission of the source' (@($copied.body.permissionIds).Count -eq $adminRolePermissions) ('copied=' + @($copied.body.permissionIds).Count + ' source=' + $adminRolePermissions)
$copyRoleId = $copied.body.roleId

$renamed = Invoke-Api 'PUT' ('/api/admin/roles/' + $copyRoleId) $adminToken @{ roleName = 'VERIFYADMIN-COPY2' }
Check 'a custom role can be renamed' ($renamed.status -eq 200) ('status=' + $renamed.status)

# ===========================================================================
# 4. A permission change reaches an already-issued token
# ===========================================================================
$before = Me $qeToken
Check 'before the change the token has no rbac:manage' (-not (@($before.permissions) -contains 'rbac:manage')) (@($before.permissions) -join ',')

$assign = Invoke-Api 'PUT' ('/api/admin/users/' + $qeEmployeeId + '/roles') $adminToken @{ roleCodes = @($liveRoleCode) }
Check 'the role is assigned' ($assign.status -eq 200) ('status=' + $assign.status + ' msg=' + $assign.message)

# The same token, no re-login: the grant must be visible at once (PS-111 AC3).
$afterGrant = Me $qeToken
Check 'the SAME token now reports the granted permission' (@($afterGrant.permissions) -contains 'report:send') (@($afterGrant.permissions) -join ',')
$adminNow = Invoke-Api 'GET' '/api/admin/users' $qeToken $null
Check 'the SAME token can now reach the admin API' ($adminNow.status -eq 200) ('status=' + $adminNow.status)

$disabled = Invoke-Api 'POST' ('/api/admin/roles/' + $liveRoleId + '/deactivate') $adminToken $null
Check 'the custom role is disabled' ($disabled.status -eq 200) ('status=' + $disabled.status)

$afterDisable = Me $qeToken
Check 'disabling the role revokes the permission on the same token' (-not (@($afterDisable.permissions) -contains 'report:send')) (@($afterDisable.permissions) -join ',')
$adminGone = Invoke-Api 'GET' '/api/admin/users' $qeToken $null
Check 'the same token is refused again (403)' ($adminGone.status -eq 403) ('status=' + $adminGone.status)

$restored = Invoke-Api 'PUT' ('/api/admin/users/' + $qeEmployeeId + '/roles') $adminToken @{ roleCodes = @($qeRoles) }
Check 'the engineer roles are restored' ($restored.status -eq 200) ('status=' + $restored.status)
$backToNormal = Me $qeToken
Check 'the token is back to its original permissions' (@($backToNormal.permissions) -contains 'rootcause:edit') (@($backToNormal.permissions) -join ',')

$deleteInUse = Invoke-Api 'DELETE' ('/api/admin/roles/' + $liveRoleId) $adminToken $null
Check 'a role nobody holds can be deleted (204)' ($deleteInUse.status -eq 204) ('status=' + $deleteInUse.status)

# The V22 fix: the name is free again once the role is gone.
$recreate = Invoke-Api 'POST' '/api/admin/roles' $adminToken @{ roleName = 'VERIFYADMIN-LIVE' }
Check 'the name can be reused after the delete (V22)' ($recreate.status -eq 201) ('status=' + $recreate.status)
$recreatedId = $recreate.body.roleId
$recreatedCode = $recreate.body.roleCode
$inUseGuard = Invoke-Api 'PUT' ('/api/admin/users/' + $qeEmployeeId + '/roles') $adminToken @{ roleCodes = @($recreatedCode) }
$deleteUsed = Invoke-Api 'DELETE' ('/api/admin/roles/' + $recreatedId) $adminToken $null
Check 'a role someone holds cannot be deleted (409)' ($deleteUsed.status -eq 409) ('status=' + $deleteUsed.status + ' assign=' + $inUseGuard.status)
Invoke-Api 'PUT' ('/api/admin/users/' + $qeEmployeeId + '/roles') $adminToken @{ roleCodes = @($qeRoles) } | Out-Null

$unknownRole = Invoke-Api 'PUT' ('/api/admin/users/' + $qeEmployeeId + '/roles') $adminToken @{ roleCodes = @('ROLE_DOES_NOT_EXIST') }
Check 'an unknown role code is refused (400)' ($unknownRole.status -eq 400) ('status=' + $unknownRole.status)

# ===========================================================================
# 5. Guard rails: the last administrator cannot be lost
# ===========================================================================
$selfDemote = Invoke-Api 'PUT' ('/api/admin/users/' + $adminEmployeeId + '/roles') $adminToken @{ roleCodes = @('ROLE_QUALITY_ENGINEER') }
Check 'an administrator cannot remove their own admin role (409)' ($selfDemote.status -eq 409) ('status=' + $selfDemote.status)

$selfOff = Invoke-Api 'POST' ('/api/admin/users/' + $adminEmployeeId + '/account/deactivate') $adminToken $null
Check 'an administrator cannot disable their own account (409)' ($selfOff.status -eq 409) ('status=' + $selfOff.status)

$lastAdmin = Invoke-Api 'POST' ('/api/admin/users/' + $adminEmployeeId + '/password/reset') $adminToken @{ newPassword = 'x' }
Check 'a too-short reset password is refused (400)' ($lastAdmin.status -eq 400) ('status=' + $lastAdmin.status)

# ===========================================================================
# 6. The permission matrix export
# ===========================================================================
$exportPath = Join-Path $cfg.outDir 'permission-matrix.xlsx'
try {
    Invoke-WebRequest -Uri ($BaseUrl + '/api/admin/permissions/matrix/export') -Method Get `
        -Headers @{ Authorization = 'Bearer ' + $adminToken } -OutFile $exportPath -UseBasicParsing -TimeoutSec 30 | Out-Null
    $exportOk = $true
} catch {
    $exportOk = $false
}
Check 'the matrix exports' $exportOk 'download failed'
if ($exportOk) {
    $bytes = [System.IO.File]::ReadAllBytes($exportPath)
    $magic = [System.Text.Encoding]::ASCII.GetString($bytes[0..1])
    Check 'the export is a real xlsx (PK)' ($magic -eq 'PK') ('magic=' + $magic)
    Check 'the export has content' ($bytes.Length -gt 2000) ('bytes=' + $bytes.Length)
}
$exportAudit = Q "select count(*) from qms.audit_log where action_type='EXPORT' and biz_type='Role';"
Check 'the export is audited' ([int]$exportAudit -ge 1) ('rows=' + $exportAudit)

# ===========================================================================
# 7. Password reset and the forced change
# ===========================================================================
$tempPassword = 'Verify@2026a'
$changedPassword = 'Verify@2026b'

$reset = Invoke-Api 'POST' ('/api/admin/users/' + $subjectId + '/password/reset') $adminToken @{ newPassword = $tempPassword }
Check 'the administrator resets the password' ($reset.status -eq 200) ('status=' + $reset.status)

$flag = Q ("select must_change_pwd from qms.user_account where employee_id='" + $subjectId + "';")
Check 'the reset flags a forced password change' ($flag -eq 't') ('must_change_pwd=' + $flag)

Check 'the old password no longer works' ($null -eq (Try-Login $subjectUser $Password)) 'old password still accepted'

$tempLogin = Try-Login $subjectUser $tempPassword
Check 'the temporary password logs in' ($null -ne $tempLogin -and $tempLogin.accessToken) 'login failed'
$tempToken = $tempLogin.accessToken
Check 'the login reports the forced change' ($tempLogin.user.mustChangePwd -eq $true) ('mustChangePwd=' + $tempLogin.user.mustChangePwd)

$meWhileFlagged = Invoke-Api 'GET' '/api/auth/me' $tempToken $null
Check 'the forced-change account may still read /auth/me' ($meWhileFlagged.status -eq 200) ('status=' + $meWhileFlagged.status)

$blocked = Invoke-Api 'GET' '/api/master-data/employees' $tempToken $null
Check 'the forced-change account is refused everywhere else (403)' ($blocked.status -eq 403) ('status=' + $blocked.status)

$wrongOld = Invoke-Api 'POST' '/api/auth/change-password' $tempToken @{ oldPassword = 'not-the-one'; newPassword = $changedPassword }
Check 'a wrong current password is refused (400)' ($wrongOld.status -eq 400) ('status=' + $wrongOld.status)

$tooShort = Invoke-Api 'POST' '/api/auth/change-password' $tempToken @{ oldPassword = $tempPassword; newPassword = 'short' }
Check 'a too-short new password is refused (400)' ($tooShort.status -eq 400) ('status=' + $tooShort.status)

$change = Invoke-Api 'POST' '/api/auth/change-password' $tempToken @{ oldPassword = $tempPassword; newPassword = $changedPassword }
Check 'the password change is accepted (204)' ($change.status -eq 204) ('status=' + $change.status)

$unblocked = Invoke-Api 'GET' '/api/master-data/employees' $tempToken $null
Check 'the same token is unblocked at once (cache invalidation)' ($unblocked.status -eq 200) ('status=' + $unblocked.status)

$newLogin = Try-Login $subjectUser $changedPassword
Check 'the new password logs in cleanly' ($null -ne $newLogin -and $newLogin.user.mustChangePwd -eq $false) 'login failed or flag still set'

# ===========================================================================
# 8. Account enable / disable
# ===========================================================================
$off = Invoke-Api 'POST' ('/api/admin/users/' + $qeEmployeeId + '/account/deactivate') $adminToken $null
Check 'the account is disabled' ($off.status -eq 200) ('status=' + $off.status)
$kicked = Invoke-Api 'GET' '/api/auth/me' $qeToken $null
Check 'a disabled account is signed out at once (401)' ($kicked.status -eq 401) ('status=' + $kicked.status)

$on = Invoke-Api 'POST' ('/api/admin/users/' + $qeEmployeeId + '/account/activate') $adminToken $null
Check 'the account is enabled again' ($on.status -eq 200) ('status=' + $on.status)
$backIn = Invoke-Api 'GET' '/api/auth/me' $qeToken $null
Check 'the enabled account can use its old token again' ($backIn.status -eq 200) ('status=' + $backIn.status)

# ===========================================================================
# 9. Login lockout and unlock
# ===========================================================================
for ($i = 0; $i -lt 5; $i++) { Try-Login $subjectUser 'definitely-wrong' | Out-Null }
Check 'five bad attempts lock the account' ($null -eq (Try-Login $subjectUser $changedPassword)) 'the correct password still worked'

$unlock = Invoke-Api 'POST' ('/api/admin/users/' + $subjectId + '/unlock') $adminToken $null
Check 'the administrator unlocks the account' ($unlock.status -eq 200) ('status=' + $unlock.status)
$afterUnlock = Try-Login $subjectUser $changedPassword
Check 'the account works again after the unlock' ($null -ne $afterUnlock) 'login failed'

$resetAudit = [int](Q ("select count(*) from qms.audit_log where action_type='PASSWORD_RESET' and biz_id='" + $subjectId + "';"))
$unlockAudit = [int](Q ("select count(*) from qms.audit_log where action_type='UNLOCK' and biz_id='" + $subjectId + "';"))
$changeAudit = [int](Q ("select count(*) from qms.audit_log where action_type='PASSWORD_CHANGE' and operator_id='" + $subjectId + "';"))
$assignAudit = [int](Q ("select count(*) from qms.audit_log where biz_type='UserRole' and biz_id='" + $qeEmployeeId + "';"))
$createAudit = [int](Q "select count(*) from qms.audit_log where action_type='CREATE' and biz_type='Role';")
Check 'a password reset was audited' ($resetAudit -ge 1) ('rows=' + $resetAudit)
Check 'an unlock was audited' ($unlockAudit -ge 1) ('rows=' + $unlockAudit)
Check 'a self password change was audited' ($changeAudit -ge 1) ('rows=' + $changeAudit)
Check 'a role assignment was audited' ($assignAudit -ge 1) ('rows=' + $assignAudit)
Check 'role creation was audited' ($createAudit -ge 1) ('rows=' + $createAudit)

# ===========================================================================
# 10. Cleanup
# ===========================================================================
if ($KeepData) {
    $lines.Add('')
    $lines.Add('  kept: role VERIFYADMIN-*, account ' + $subjectUser)
} else {
    # Put the seeded account back exactly as it was, hash and all.
    Q ("update qms.user_account set password_hash = '" + $subjectHash + "', must_change_pwd = false, failed_attempts = 0, locked_until = null where employee_id = '" + $subjectId + "';") | Out-Null
    # Remove the roles this script made, and every link that pointed at them.
    Q "delete from qms.role_permission where role_id in (select role_id from qms.role where role_name like 'VERIFYADMIN-%');" | Out-Null
    Q "delete from qms.user_role where role_id in (select role_id from qms.role where role_name like 'VERIFYADMIN-%');" | Out-Null
    Q "delete from qms.role where role_name like 'VERIFYADMIN-%';" | Out-Null
    $leftRoles = Q "select count(*) from qms.role where role_name like 'VERIFYADMIN-%';"
    $leftLinks = Q ("select count(*) from qms.user_role where employee_id = '" + $qeEmployeeId + "' and role_id not in (select role_id from qms.role);")
    $lines.Add('')
    $lines.Add('  cleaned up; leftover test roles=' + $leftRoles + ' orphan links=' + $leftLinks)
}

$lines.Add('')
$lines.Add(('  RESULT : ' + $(if ($fail -eq 0) { 'PASS' } else { "FAIL ($fail)" }) + '   passed=' + $pass + ' failed=' + $fail))
$lines | Set-Content -Path (Join-Path $cfg.outDir 'verify_admin_report.txt') -Encoding UTF8
$lines | ForEach-Object { [Console]::Out.WriteLine($_) }
if ($fail -ne 0) { exit 1 }
