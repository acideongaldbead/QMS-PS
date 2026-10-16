package com.nexperia.qms.auth;

import com.baomidou.mybatisplus.core.toolkit.Wrappers;
import com.nexperia.qms.auth.mapper.AuthMapper;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.boot.ApplicationArguments;
import org.springframework.boot.ApplicationRunner;
import org.springframework.boot.SpringApplication;
import org.springframework.context.ApplicationContext;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.stereotype.Component;

import java.util.List;

/**
 * One-shot administrator utility that sets an account password.
 *
 * A fresh install has seeded accounts still holding the 'CHANGE_ME' sentinel,
 * and LocalPasswordAuthProvider refuses to authenticate those -- which is
 * correct (the repository must never carry a password hash) but leaves no way
 * in until an administrator sets a password. This is that way in, and it is
 * also the supported route for resetting a forgotten password later.
 *
 * Run it as a CLI, never as part of the service. reset-password.ps1 wraps:
 *   java -jar qms-api.jar --spring.profiles.active=prod
 *        --spring.config.additional-location=file:&lt;install&gt;/config/
 *        --server.port=0 --server.ssl.enabled=false
 *        --qms.admin.set-password=&lt;username&gt;
 * with the new password in the QMS_NEW_PASSWORD environment variable, so it
 * never lands on the command line (and therefore never in the process list or
 * the shell history). The context is still a full web one -- Tomcat binds an
 * ephemeral port (0) and TLS is switched off, so the CLI needs neither the real
 * port nor the keystore, and it cannot collide with a running service.
 *
 * The option is absent during a normal service start, in which case run() is a
 * no-op.
 */
@Component
public class AdminPasswordCli implements ApplicationRunner {

    private static final Logger log = LoggerFactory.getLogger(AdminPasswordCli.class);

    private static final String OPTION = "qms.admin.set-password";
    private static final String ENV_VAR = "QMS_NEW_PASSWORD";
    private static final String SENTINEL = "CHANGE_ME";
    private static final int MIN_LENGTH = 8;

    /** Exit codes, so the wrapper script can tell the failure modes apart. */
    private static final int OK = 0;
    private static final int BAD_USAGE = 2;
    private static final int NO_SUCH_ACCOUNT = 3;

    private final AuthMapper authMapper;
    private final PasswordEncoder passwordEncoder;
    private final ApplicationContext context;

    public AdminPasswordCli(AuthMapper authMapper, PasswordEncoder passwordEncoder, ApplicationContext context) {
        this.authMapper = authMapper;
        this.passwordEncoder = passwordEncoder;
        this.context = context;
    }

    @Override
    public void run(ApplicationArguments args) {
        if (!args.containsOption(OPTION)) {
            return;
        }
        int exitCode = execute(args.getOptionValues(OPTION));
        // Exit the JVM: without this the context stays up and the CLI appears to hang.
        System.exit(SpringApplication.exit(context, () -> exitCode));
    }

    private int execute(List<String> values) {
        if (values == null || values.isEmpty() || values.get(0) == null || values.get(0).isBlank()) {
            log.error("Usage: --{}=<username>, with the new password in the {} environment variable.",
                    OPTION, ENV_VAR);
            return BAD_USAGE;
        }
        String username = values.get(0).trim();

        String password = System.getenv(ENV_VAR);
        if (password == null || password.isBlank()) {
            log.error("Environment variable {} is not set.", ENV_VAR);
            return BAD_USAGE;
        }
        if (password.length() < MIN_LENGTH) {
            log.error("The new password must be at least {} characters.", MIN_LENGTH);
            return BAD_USAGE;
        }

        UserAccount account = authMapper.selectOne(
                Wrappers.<UserAccount>lambdaQuery().eq(UserAccount::getUsername, username));
        if (account == null) {
            log.error("No account with username '{}'.", username);
            return NO_SUCH_ACCOUNT;
        }

        boolean wasSentinel = SENTINEL.equals(account.getPasswordHash());
        authMapper.setPasswordHash(account.getAccountId(), passwordEncoder.encode(password));
        authMapper.clearLock(account.getAccountId());

        log.info("Password set for '{}' (employee {}, account {}). Lockout cleared.{}",
                username, account.getEmployeeId(), account.getAccountId(),
                wasSentinel ? " The account was on the seed sentinel and is now usable." : "");
        return OK;
    }
}
