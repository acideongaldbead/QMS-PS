package com.nexperia.qms.auth;

import com.nexperia.qms.auth.mapper.AuthMapper;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.boot.ApplicationArguments;
import org.springframework.boot.ApplicationRunner;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.stereotype.Component;

import java.util.List;

/**
 * Gives the seeded accounts a working password.
 *
 * V9 writes the sentinel 'CHANGE_ME' so the repository never contains a password
 * hash. On startup, under a profile that sets qms.auth.dev-password, this
 * replaces the sentinel with a real BCrypt hash of that password. Every other
 * environment leaves the sentinel in place and accounts cannot be used until an
 * administrator sets a password.
 */
@Component
@ConditionalOnProperty(name = "qms.auth.dev-password")
public class LocalPasswordInitializer implements ApplicationRunner {

    private static final Logger log = LoggerFactory.getLogger(LocalPasswordInitializer.class);

    private final AuthMapper authMapper;
    private final PasswordEncoder passwordEncoder;
    private final String devPassword;

    public LocalPasswordInitializer(AuthMapper authMapper,
                                    PasswordEncoder passwordEncoder,
                                    @org.springframework.beans.factory.annotation.Value("${qms.auth.dev-password}") String devPassword) {
        this.authMapper = authMapper;
        this.passwordEncoder = passwordEncoder;
        this.devPassword = devPassword;
    }

    @Override
    public void run(ApplicationArguments args) {
        List<Long> accountIds = authMapper.findAccountsWithPlaceholderPassword();
        if (accountIds.isEmpty()) {
            return;
        }
        // A separate hash per account so the BCrypt salts differ.
        for (Long accountId : accountIds) {
            authMapper.setPasswordHash(accountId, passwordEncoder.encode(devPassword));
        }
        log.warn("Set the development password on {} seeded account(s). "
                + "This is for local/demo use only and must not be enabled in production.", accountIds.size());
    }
}
