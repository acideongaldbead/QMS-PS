package com.nexperia.qms.auth;

import com.baomidou.mybatisplus.core.toolkit.Wrappers;
import com.nexperia.qms.auth.mapper.AuthMapper;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.security.authentication.BadCredentialsException;
import org.springframework.security.authentication.DisabledException;
import org.springframework.security.authentication.LockedException;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.stereotype.Component;

import java.time.OffsetDateTime;
import java.util.Optional;

/**
 * Username + BCrypt password against {@code user_account}. Consecutive failures
 * lock the account for a cooling-off period (requirement 3.16).
 */
@Component
public class LocalPasswordAuthProvider implements AuthProvider {

    private static final Logger log = LoggerFactory.getLogger(LocalPasswordAuthProvider.class);
    private static final String CHANGE_ME = "CHANGE_ME";

    private final AuthMapper authMapper;
    private final PasswordEncoder passwordEncoder;
    private final boolean enabled;
    private final int maxFailedAttempts;
    private final int lockMinutes;

    public LocalPasswordAuthProvider(
            AuthMapper authMapper,
            PasswordEncoder passwordEncoder,
            @Value("${qms.auth.sso.enabled:false}") boolean ssoEnabled,
            @Value("${qms.auth.lockout.max-failed-attempts:5}") int maxFailedAttempts,
            @Value("${qms.auth.lockout.lock-minutes:15}") int lockMinutes) {
        this.authMapper = authMapper;
        this.passwordEncoder = passwordEncoder;
        this.enabled = !ssoEnabled;
        this.maxFailedAttempts = maxFailedAttempts;
        this.lockMinutes = lockMinutes;
    }

    @Override
    public String name() {
        return "local";
    }

    @Override
    public boolean isEnabled() {
        return enabled;
    }

    @Override
    public Optional<String> authenticate(String username, String rawPassword) {
        UserAccount account = authMapper.selectOne(
                Wrappers.<UserAccount>lambdaQuery()
                        .eq(UserAccount::getUsername, username)
                        .eq(UserAccount::getIsActive, true));

        // Same generic failure whether the account is unknown or the password is
        // wrong, so the response cannot be used to enumerate usernames.
        if (account == null) {
            log.debug("login rejected: unknown username '{}'", username);
            throw new BadCredentialsException("账号或密码错误");
        }

        if (account.getLockedUntil() != null && account.getLockedUntil().isAfter(OffsetDateTime.now())) {
            throw new LockedException("账号已锁定，请稍后再试，或联系管理员解锁");
        }

        if (CHANGE_ME.equals(account.getPasswordHash())) {
            throw new DisabledException("该账号尚未设置口令，请联系管理员");
        }

        if (!passwordEncoder.matches(rawPassword, account.getPasswordHash())) {
            int failures = (account.getFailedAttempts() == null ? 0 : account.getFailedAttempts()) + 1;
            OffsetDateTime lockedUntil = failures >= maxFailedAttempts
                    ? OffsetDateTime.now().plusMinutes(lockMinutes)
                    : null;
            authMapper.markLoginFailure(account.getAccountId(), failures, lockedUntil);
            log.info("failed login for '{}' (attempt {} of {})", username, failures, maxFailedAttempts);
            if (lockedUntil != null) {
                throw new LockedException("连续登录失败次数过多，账号已锁定 " + lockMinutes + " 分钟");
            }
            throw new BadCredentialsException("账号或密码错误");
        }

        authMapper.markLoginSuccess(account.getAccountId());
        return Optional.of(account.getEmployeeId());
    }
}
