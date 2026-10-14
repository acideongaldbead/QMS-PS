package com.nexperia.qms.common.storage;

import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.stereotype.Component;

import java.nio.file.Path;

/**
 * Does not scan. Used while no approved scanner endpoint exists, and it says so
 * in its result rather than pretending the file was checked -- the audit entry
 * then records "not scanned", which is the honest state of affairs.
 */
@Component
@ConditionalOnProperty(name = "qms.antivirus.provider", havingValue = "noop", matchIfMissing = true)
public class NoopAntivirusScanner implements AntivirusScanner {

    @Override
    public String name() {
        return "noop";
    }

    @Override
    public ScanResult scan(Path file) {
        return ScanResult.clean("未配置杀毒服务，未执行扫描");
    }
}
