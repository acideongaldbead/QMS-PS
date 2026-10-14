package com.nexperia.qms.report.mail;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.stereotype.Component;

/**
 * Does not send. Used while no mail relay is configured, and it says so in the
 * log rather than pretending the customer was reached -- the communication log
 * still records the send, which is the honest state of affairs.
 */
@Component
@ConditionalOnProperty(name = "qms.mail.provider", havingValue = "noop", matchIfMissing = true)
public class NoopReportMailer implements ReportMailer {

    private static final Logger log = LoggerFactory.getLogger(NoopReportMailer.class);

    @Override
    public String name() {
        return "noop";
    }

    @Override
    public void send(ReportMail mail) {
        log.info("qms.mail.provider=noop: not sending '{}' to {} ({} attachment byte(s)); "
                        + "the communication log is still written",
                mail.subject(), mail.to(), mail.attachment() == null ? 0 : mail.attachment().length);
    }
}
