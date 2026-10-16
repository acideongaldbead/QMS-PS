package com.nexperia.qms.auth;

import com.baomidou.mybatisplus.core.toolkit.Wrappers;
import com.nexperia.qms.auth.dto.ChangePasswordRequest;
import com.nexperia.qms.auth.dto.LoginResult;
import com.nexperia.qms.auth.dto.MeResponse;
import com.nexperia.qms.auth.mapper.AuthMapper;
import com.nexperia.qms.common.audit.AuditActions;
import com.nexperia.qms.common.audit.AuditLogService;
import com.nexperia.qms.common.security.CurrentUser;
import com.nexperia.qms.common.security.JwtService;
import com.nexperia.qms.common.security.PasswordPolicy;
import com.nexperia.qms.common.security.PermissionCache;
import org.springframework.security.authentication.BadCredentialsException;
import org.springframework.security.core.Authentication;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.util.List;

@Service
public class AuthService {

    private final List<AuthProvider> providers;
    private final AuthMapper authMapper;
    private final JwtService jwtService;
    private final PermissionCache permissionCache;
    private final PasswordEncoder passwordEncoder;
    private final AuditLogService auditLogService;

    public AuthService(List<AuthProvider> providers,
                       AuthMapper authMapper,
                       JwtService jwtService,
                       PermissionCache permissionCache,
                       PasswordEncoder passwordEncoder,
                       AuditLogService auditLogService) {
        this.providers = providers;
        this.authMapper = authMapper;
        this.jwtService = jwtService;
        this.permissionCache = permissionCache;
        this.passwordEncoder = passwordEncoder;
        this.auditLogService = auditLogService;
    }

    public LoginResult login(String username, String rawPassword) {
        AuthProvider provider = providers.stream()
                .filter(AuthProvider::isEnabled)
                .findFirst()
                .orElseThrow(() -> new IllegalStateException("No authentication provider is enabled"));

        String employeeId = provider.authenticate(username, rawPassword)
                .orElseThrow(() -> new BadCredentialsException("账号或密码错误"));

        CurrentUser user = loadUser(employeeId, username);
        return new LoginResult(jwtService.createAccessToken(user), toMe(user));
    }

    /**
     * Rebuilds the principal from the database, at login and on /api/auth/me.
     *
     * The same content is resolved per request by JwtAuthFilter through the same
     * cache, so /me and the authorities a request runs under cannot disagree.
     */
    public CurrentUser loadUser(String employeeId, String username) {
        PermissionCache.AuthState state = permissionCache.get(employeeId);
        return new CurrentUser(
                employeeId,
                username,
                state.roles(),
                state.permissions(),
                state.mustChangePwd());
    }

    /**
     * Changes the caller's own password. Used both for the forced first change and
     * for a voluntary one; clearing the flag is what makes it the former.
     */
    @Transactional
    public void changePassword(Authentication authentication, ChangePasswordRequest request) {
        CurrentUser user = requirePrincipal(authentication);
        UserAccount account = authMapper.selectOne(
                Wrappers.<UserAccount>lambdaQuery().eq(UserAccount::getEmployeeId, user.employeeId()));
        if (account == null) {
            throw new BadCredentialsException("账号不存在");
        }
        // A wrong current password is reported as 400, not 401: the frontend signs a
        // 401 out, and being logged out mid-form for a typo would be absurd.
        if (account.getPasswordHash() == null
                || !passwordEncoder.matches(request.oldPassword(), account.getPasswordHash())) {
            throw new IllegalArgumentException("当前口令不正确");
        }
        PasswordPolicy.requireAcceptable(request.newPassword());
        if (passwordEncoder.matches(request.newPassword(), account.getPasswordHash())) {
            throw new IllegalArgumentException("新口令不能与当前口令相同");
        }

        authMapper.setOwnPassword(account.getAccountId(),
                passwordEncoder.encode(request.newPassword()), user.employeeId());
        auditLogService.record(AuditActions.PASSWORD_CHANGE, "UserAccount", user.employeeId(), "修改本人登录口令");
        // The forced-change flag lives in the cache, so the next request must see
        // the cleared value rather than waiting out the TTL.
        permissionCache.invalidateAfterCommit(user.employeeId());
    }

    public MeResponse toMe(CurrentUser user) {
        EmployeeProfile profile = authMapper.findProfile(user.employeeId());
        return new MeResponse(
                user.employeeId(),
                user.username(),
                profile == null ? null : profile.getName(),
                profile == null ? null : profile.getNameEn(),
                profile == null ? null : profile.getEmail(),
                profile == null ? null : profile.getDeptL1(),
                profile == null ? null : profile.getDeptL2(),
                profile == null ? null : profile.getJobTitle(),
                user.roles().stream().sorted().toList(),
                user.permissions().stream().sorted().toList(),
                user.mustChangePwd());
    }

    public MeResponse me(Authentication authentication) {
        return toMe(requirePrincipal(authentication));
    }

    private CurrentUser requirePrincipal(Authentication authentication) {
        if (authentication == null || !(authentication.getPrincipal() instanceof CurrentUser user)) {
            throw new BadCredentialsException("未登录");
        }
        return user;
    }
}
