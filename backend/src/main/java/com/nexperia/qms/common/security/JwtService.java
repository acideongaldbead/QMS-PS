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
import java.util.List;

/**
 * Signs and reads access tokens.
 *
 * The token carries the identity only -- {@code sub} is the employee id, plus the
 * username. Roles and permissions are deliberately NOT trusted from the token:
 * {@link JwtAuthFilter} reads them from the database on every request (through
 * {@link PermissionCache}), so revoking or granting a permission takes effect at
 * once rather than when the token expires (requirement 3.12, PS-111 AC3).
 *
 * The {@code roles} / {@code perms} claims are still written so a token minted
 * before this change stays valid for its remaining lifetime, but nothing reads
 * them any more -- the filter only needs the identity to look the rest up.
 */
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

    /** Everything a token is entitled to assert on its own. */
    public record TokenIdentity(String employeeId, String username) {
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

    /**
     * Verifies the signature and the expiry and returns the identity, or
     * {@code null} when the token is not a valid, unexpired one.
     *
     * A single parse: the previous isValid() + parseAccessToken() pair verified
     * the same token twice on every request.
     */
    public TokenIdentity parseIdentity(String token) {
        try {
            Claims claims = Jwts.parser().verifyWith(key).build()
                    .parseSignedClaims(token)
                    .getPayload();
            return new TokenIdentity(claims.getSubject(), claims.get("username", String.class));
        } catch (JwtException | IllegalArgumentException e) {
            return null;
        }
    }
}
