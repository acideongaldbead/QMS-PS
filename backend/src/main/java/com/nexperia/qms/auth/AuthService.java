package com.nexperia.qms.auth;

import com.nexperia.qms.auth.dto.LoginResult;
import com.nexperia.qms.auth.dto.MeResponse;
import com.nexperia.qms.auth.mapper.AuthMapper;
import com.nexperia.qms.common.security.CurrentUser;
import com.nexperia.qms.common.security.JwtService;
import org.springframework.security.authentication.BadCredentialsException;
import org.springframework.security.core.Authentication;
import org.springframework.stereotype.Service;

import java.util.HashSet;
import java.util.List;

@Service
public class AuthService {

    private final List<AuthProvider> providers;
    private final AuthMapper authMapper;
    private final JwtService jwtService;

    public AuthService(List<AuthProvider> providers, AuthMapper authMapper, JwtService jwtService) {
        this.providers = providers;
        this.authMapper = authMapper;
        this.jwtService = jwtService;
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
     * Rebuilds the principal from the database. Called at login and by
     * /api/auth/me, not per request: the access token itself carries the
     * permission codes, so a permission change is picked up on the next login
     * or when the client refreshes /me.
     */
    public CurrentUser loadUser(String employeeId, String username) {
        List<String> roles = authMapper.findRoleCodes(employeeId);
        List<String> permissions = authMapper.findPermissionCodes(employeeId);
        return new CurrentUser(
                employeeId,
                username,
                new HashSet<>(roles),
                new HashSet<>(permissions));
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
                user.permissions().stream().sorted().toList());
    }

    public MeResponse me(Authentication authentication) {
        if (authentication == null || !(authentication.getPrincipal() instanceof CurrentUser user)) {
            throw new BadCredentialsException("未登录");
        }
        return toMe(user);
    }
}
