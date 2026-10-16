package com.nexperia.qms.common.security;

import com.fasterxml.jackson.databind.ObjectMapper;
import jakarta.servlet.FilterChain;
import jakarta.servlet.ServletException;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import org.springframework.http.MediaType;
import org.springframework.lang.NonNull;
import org.springframework.security.authentication.UsernamePasswordAuthenticationToken;
import org.springframework.security.core.authority.SimpleGrantedAuthority;
import org.springframework.security.core.context.SecurityContextHolder;
import org.springframework.stereotype.Component;
import org.springframework.web.filter.OncePerRequestFilter;

import java.io.IOException;
import java.util.List;
import java.util.Map;

/**
 * Reads a Bearer token, verifies it, and publishes the principal both to the
 * Spring Security context (for @PreAuthorize) and to {@link CurrentUserContext}
 * (for audit fields).
 *
 * The token only supplies the identity. Roles, permissions and the account flags
 * come from {@link PermissionCache}, which reads the database, so:
 *   - revoking a permission (or disabling a role) applies to an already-open
 *     session on its very next request -- requirement 3.12, PS-111 AC3;
 *   - disabling an account takes effect the same way: no authorities are
 *     published, so the request falls through to 401;
 *   - an account flagged must_change_pwd is confined to the endpoints it needs to
 *     change its password.
 */
@Component
public class JwtAuthFilter extends OncePerRequestFilter {

    private static final String HEADER = "Authorization";
    private static final String PREFIX = "Bearer ";

    /** Reachable while a forced password change is still pending. */
    private static final String CHANGE_PASSWORD_PATH = "/api/auth/change-password";
    private static final String ME_PATH = "/api/auth/me";
    private static final String I18N_PREFIX = "/api/i18n/";

    private final JwtService jwtService;
    private final PermissionCache permissionCache;
    private final ObjectMapper objectMapper;

    public JwtAuthFilter(JwtService jwtService, PermissionCache permissionCache, ObjectMapper objectMapper) {
        this.jwtService = jwtService;
        this.permissionCache = permissionCache;
        this.objectMapper = objectMapper;
    }

    @Override
    protected void doFilterInternal(@NonNull HttpServletRequest request,
                                    @NonNull HttpServletResponse response,
                                    @NonNull FilterChain chain) throws ServletException, IOException {
        try {
            String header = request.getHeader(HEADER);
            if (header != null && header.startsWith(PREFIX)) {
                String token = header.substring(PREFIX.length()).trim();
                JwtService.TokenIdentity identity = jwtService.parseIdentity(token);
                if (identity != null) {
                    PermissionCache.AuthState state = permissionCache.get(identity.employeeId());
                    if (state.active()) {
                        CurrentUser user = new CurrentUser(
                                identity.employeeId(),
                                identity.username(),
                                state.roles(),
                                state.permissions(),
                                state.mustChangePwd());
                        CurrentUserContext.set(user);

                        List<SimpleGrantedAuthority> authorities = state.permissions().stream()
                                .map(SimpleGrantedAuthority::new)
                                .toList();
                        var authentication = new UsernamePasswordAuthenticationToken(user, null, authorities);
                        SecurityContextHolder.getContext().setAuthentication(authentication);

                        if (state.mustChangePwd() && !isAllowedDuringPasswordChange(request.getRequestURI())) {
                            writeJson(response, HttpServletResponse.SC_FORBIDDEN,
                                    "请先修改初始口令后再使用系统");
                            return;
                        }
                    }
                    // A disabled account publishes no authorities, so /api/** answers
                    // 401 through the entry point -- an immediate sign-out.
                }
            }
            chain.doFilter(request, response);
        } finally {
            CurrentUserContext.clear();
            SecurityContextHolder.clearContext();
        }
    }

    private static boolean isAllowedDuringPasswordChange(String uri) {
        return ME_PATH.equals(uri) || CHANGE_PASSWORD_PATH.equals(uri) || uri.startsWith(I18N_PREFIX);
    }

    private void writeJson(HttpServletResponse response, int status, String message) throws IOException {
        response.setStatus(status);
        response.setContentType(MediaType.APPLICATION_JSON_VALUE);
        response.setCharacterEncoding("UTF-8");
        objectMapper.writeValue(response.getWriter(), Map.of("status", status, "message", message));
    }
}
