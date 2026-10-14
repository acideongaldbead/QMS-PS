package com.nexperia.qms.report.mail;

import jakarta.mail.MessagingException;
import jakarta.mail.internet.MimeMessage;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.core.io.ByteArrayResource;
import org.springframework.mail.javamail.JavaMailSender;
import org.springframework.mail.javamail.MimeMessageHelper;
import org.springframework.stereotype.Component;

/**
 * Really sends. Selected by {@code qms.mail.provider=smtp}, which also requires
 * spring.mail.* to be configured -- the {@link JavaMailSender} bean only exists
 * once spring.mail.host is set (host/username/password come from config\.env).
 */
@Component
@ConditionalOnProperty(name = "qms.mail.provider", havingValue = "smtp")
public class SmtpReportMailer implements ReportMailer {

    private final JavaMailSender mailSender;
    private final MailProperties properties;

    public SmtpReportMailer(JavaMailSender mailSender, MailProperties properties) {
        this.mailSender = mailSender;
        this.properties = properties;
    }

    @Override
    public String name() {
        return "smtp";
    }

    @Override
    public void send(ReportMail mail) {
        try {
            MimeMessage message = mailSender.createMimeMessage();
            MimeMessageHelper helper = new MimeMessageHelper(message, true, "UTF-8");
            helper.setFrom(properties.getFromAddress());
            helper.setTo(mail.to().toArray(String[]::new));
            if (mail.cc() != null && !mail.cc().isEmpty()) {
                helper.setCc(mail.cc().toArray(String[]::new));
            }
            helper.setSubject(mail.subject());
            helper.setText(mail.body(), false);
            if (mail.attachment() != null && mail.attachment().length > 0) {
                helper.addAttachment(mail.attachmentName(), new ByteArrayResource(mail.attachment()));
            }
            mailSender.send(message);
        } catch (MessagingException e) {
            // Surface it as a business failure so the caller's transaction rolls
            // back and no communication log claims a send that never happened.
            throw new IllegalStateException("报告邮件发送失败：" + e.getMessage(), e);
        }
    }
}
