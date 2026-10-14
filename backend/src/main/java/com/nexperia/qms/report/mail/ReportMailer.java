package com.nexperia.qms.report.mail;

import java.util.List;

/**
 * Sends the 8D report to the customer (requirement 3.9).
 *
 * A pluggable hook, like the antivirus scanner: phase 1 defaults to
 * {@link NoopReportMailer} while no relay is configured, and
 * {@link SmtpReportMailer} is selected once spring.mail.* is set.
 */
public interface ReportMailer {

    /** Human-readable name, recorded with the send. */
    String name();

    void send(ReportMail mail);

    record ReportMail(
            List<String> to,
            List<String> cc,
            String subject,
            String body,
            String attachmentName,
            byte[] attachment) {
    }
}
