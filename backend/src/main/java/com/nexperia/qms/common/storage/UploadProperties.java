package com.nexperia.qms.common.storage;

import lombok.Data;
import org.springframework.boot.context.properties.ConfigurationProperties;
import org.springframework.stereotype.Component;

import java.util.ArrayList;
import java.util.List;

/**
 * Upload rules from qms.upload.* (requirement Q-15 / NFR-15).
 *
 * A typed holder rather than @Value: `allowed-extensions` is a YAML list, and
 * @Value cannot resolve a list-valued property -- it fails at startup with
 * "Could not resolve placeholder".
 */
@Component
@ConfigurationProperties(prefix = "qms.upload")
@Data
public class UploadProperties {

    /** File extensions accepted, without the dot. */
    private List<String> allowedExtensions = new ArrayList<>();

    /** Largest single file, in bytes. */
    private long maxBytes = 50L * 1024 * 1024;
}
