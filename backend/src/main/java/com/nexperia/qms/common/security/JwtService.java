package com.nexperia.qms.common.security;

import io.jsonwebtoken.Claims;
import io.jsonwebtoken.JwtException;
import io.jsonwebtoken.Jwts;
import io.jsonwebtoken.security.Keys;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Service;

import javax.crypto.SecretKey;
import java.nio.charset.StandardCharsets;
import java.time.Duration;
import java.time.Instant;
import java.util.Date;
import java.util.HashSet;
import java.util.List;
import java.util.Set;

@Service
public class JwtService {

    private final SecretKey key;
    private final Duration accessTtl;

    public JwtService(
            @Value("${qms.jwt.secret}") String secret,
            @Value("${qms.jwt.access-token-minutes:30}") long accessMinutes) {
        byte[] bytes = secret.getBytes(StandardCharsets.UTF_8);
        if (bytes.length < 32) {
            throw new IllegalStateException(
                    "qms.jwt.secret must be at least 32 bytes for HS256; set QMS_JWT_SECRET");
        }
        this.key = Keys.hmacShaKeyFor(bytes);
        this.accessTtl = Duration.ofMinutes(accessMinutes);
    }

    public String createAccessToken(CurrentUser user) {
        Instant now = Instant.now();
        return Jwts.builder()
                .subject(user.employeeId())
                .claim("username", user.username())
                .claim("roles", List.copyOf(user.roles()))
                .claim("perms", List.copyOf(user.permissions()))
                .issuedAt(Date.from(now))
                .expiration(Date.from(now.plus(accessTtl)))
                .signWith(key)
                .compact();
    }

    /** Parses and verifies an access token, rebuilding the principal. */
    public CurrentUser parseAccessToken(String token) {
        Claims claims = Jwts.parser().verifyWith(key).build()
                .parseSignedClaims(token)
                .getPayload();
        return new CurrentUser(
                claims.getSubject(),
                claims.get("username", String.class),
                toStringSet(claims.get("roles")),
                toStringSet(claims.get("perms")));
    }

    public boolean isValid(String token) {
        try {
            Jwts.parser().verifyWith(key).build().parseSignedClaims(token);
            return true;
        } catch (JwtException | IllegalArgumentException e) {
            return false;
        }
    }

    private static Set<String> toStringSet(Object raw) {
        if (!(raw instanceof List<?> list)) {
            return Set.of();
        }
        Set<String> out = new HashSet<>();
        for (Object o : list) {
            if (o != null) {
                out.add(o.toString());
            }
        }
        return out;
    }
}
