package com.nexperia.qms.report.mail;

import lombok.Data;
import org.springframework.boot.context.properties.ConfigurationProperties;
import org.springframework.stereotype.Component;

/**
 * Mail settings from qms.mail.*.
 *
 * {@code provider} mirrors the antivirus switch: {@code noop} (default) records
 * the send without touching a mail server, {@code smtp} really sends and requires
 * spring.mail.* to be configured (host/username/password in config\.env).
 */
@Component
@ConfigurationProperties(prefix = "qms.mail")
@Data
public class MailProperties {

    private String provider = "noop";

    /** The envelope From; the requirement wants the sender to be the Sales Quality user. */
    private String fromAddress = "qms-noreply@nexperia.com";
}
