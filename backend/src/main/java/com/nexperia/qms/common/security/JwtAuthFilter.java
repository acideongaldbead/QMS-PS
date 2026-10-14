package com.nexperia.qms.common.security;

import jakarta.servlet.FilterChain;
import jakarta.servlet.ServletException;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import org.springframework.lang.NonNull;
import org.springframework.security.authentication.UsernamePasswordAuthenticationToken;
import org.springframework.security.core.authority.SimpleGrantedAuthority;
import org.springframework.security.core.context.SecurityContextHolder;
import org.springframework.stereotype.Component;
import org.springframework.web.filter.OncePerRequestFilter;

import java.io.IOException;
import java.util.List;

/**
 * Reads a Bearer token, verifies it, and publishes the principal both to the
 * Spring Security context (for @PreAuthorize) and to {@link CurrentUserContext}
 * (for audit fields).
 */
@Component
public class JwtAuthFilter extends OncePerRequestFilter {

    private static final String HEADER = "Authorization";
    private static final String PREFIX = "Bearer ";

    private final JwtService jwtService;

    public JwtAuthFilter(JwtService jwtService) {
        this.jwtService = jwtService;
    }

    @Override
    protected void doFilterInternal(@NonNull HttpServletRequest request,
                                    @NonNull HttpServletResponse response,
                                    @NonNull FilterChain chain) throws ServletException, IOException {
        try {
            String header = request.getHeader(HEADER);
            if (header != null && header.startsWith(PREFIX)) {
                String token = header.substring(PREFIX.length()).trim();
                if (jwtService.isValid(token)) {
                    CurrentUser user = jwtService.parseAccessToken(token);
                    CurrentUserContext.set(user);

                    List<SimpleGrantedAuthority> authorities = user.permissions().stream()
                            .map(SimpleGrantedAuthority::new)
                            .toList();
                    var authentication = new UsernamePasswordAuthenticationToken(user, null, authorities);
                    SecurityContextHolder.getContext().setAuthentication(authentication);
                }
            }
            chain.doFilter(request, response);
        } finally {
            CurrentUserContext.clear();
            SecurityContextHolder.clearContext();
        }
    }
}
