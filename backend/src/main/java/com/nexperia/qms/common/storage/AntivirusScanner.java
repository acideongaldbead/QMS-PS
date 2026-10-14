package com.nexperia.qms.common.storage;

import java.nio.file.Path;

/**
 * Virus scanning hook. Requirement Q-15 says a file is scanned as it is uploaded.
 *
 * Phase 1 runs {@link NoopAntivirusScanner} because no company-approved scanner
 * has been nominated yet; {@link ClamAvScanner} speaks the clamd protocol and is
 * selected by configuration once IT provides an endpoint.
 */
public interface AntivirusScanner {

    /** Human-readable name, reported on the attachment row's audit entry. */
    String name();

    ScanResult scan(Path file);

    record ScanResult(boolean clean, String detail) {

        public static ScanResult clean(String detail) {
            return new ScanResult(true, detail);
        }

        public static ScanResult infected(String detail) {
            return new ScanResult(false, detail);
        }
    }
}
