package com.nexperia.qms.common.security;

import com.github.benmanes.caffeine.cache.Cache;
import com.github.benmanes.caffeine.cache.Caffeine;
import com.nexperia.qms.auth.AccountAuthState;
import com.nexperia.qms.auth.mapper.AuthMapper;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Component;
import org.springframework.transaction.support.TransactionSynchronization;
import org.springframework.transaction.support.TransactionSynchronizationManager;

import java.time.Duration;
import java.util.HashSet;
import java.util.Set;

/**
 * The authorization state of one employee, read from the database rather than
 * taken from the access token.
 *
 * Requirement 3.12 (PS-111 AC3) says a permission change takes effect at once.
 * That rules out baking the permission codes into the JWT at login, which is what
 * the application used to do. Instead the filter resolves them here on every
 * request, and this cache keeps that from becoming a query per request. The TTL is
 * only a backstop: correctness comes from the explicit invalidations the
 * administration services perform after a write commits.
 *
 * A plain Caffeine instance rather than {@code @Cacheable}: the project has the
 * Caffeine dependency but not {@code spring-boot-starter-cache}, and one small
 * cache with an explicit API is clearer than annotating four loaders.
 */
@Component
public class PermissionCache {

    /** What a request is allowed to know about its caller. */
    public record AuthState(boolean active, boolean mustChangePwd, Set<String> roles, Set<String> permissions) {

        static AuthState inactive() {
            return new AuthState(false, false, Set.of(), Set.of());
        }
    }

    private final AuthMapper authMapper;
    private final Cache<String, AuthState> cache;

    public PermissionCache(AuthMapper authMapper,
                           @Value("${qms.auth.permission-cache-seconds:60}") long cacheSeconds) {
        this.authMapper = authMapper;
        this.cache = Caffeine.newBuilder()
                .expireAfterWrite(Duration.ofSeconds(Math.max(1, cacheSeconds)))
                .maximumSize(10_000)
                .build();
    }

    public AuthState get(String employeeId) {
        return cache.get(employeeId, this::load);
    }

    private AuthState load(String employeeId) {
        AccountAuthState account = authMapper.findAccountState(employeeId);
        // No account row (an employee nobody has opened an account for) is treated
        // the same as a disabled one: there is no one to authenticate.
        if (account == null || !account.active()) {
            return AuthState.inactive();
        }
        return new AuthState(
                true,
                account.mustChangePwd(),
                new HashSet<>(authMapper.findRoleCodes(employeeId)),
                new HashSet<>(authMapper.findPermissionCodes(employeeId)));
    }

    /**
     * Drops every entry. For a change that can affect anyone: editing a role's
     * permissions, copying, renaming, disabling or deleting a role.
     */
    public void invalidateAllAfterCommit() {
        runAfterCommit(cache::invalidateAll);
    }

    /** Drops one employee's entry. For a change that only affects them. */
    public void invalidateAfterCommit(String employeeId) {
        runAfterCommit(() -> cache.invalidate(employeeId));
    }

    /**
     * Waits for the surrounding transaction to commit before dropping the entry.
     *
     * Invalidating while the transaction is still open would let a concurrent
     * request on another thread reload the pre-commit row and re-cache it, pinning
     * the old permissions for a whole TTL -- the exact opposite of the intent.
     */
    private void runAfterCommit(Runnable action) {
        if (TransactionSynchronizationManager.isSynchronizationActive()) {
            TransactionSynchronizationManager.registerSynchronization(new TransactionSynchronization() {
                @Override
                public void afterCommit() {
                    action.run();
                }
            });
        } else {
            action.run();
        }
    }
}
