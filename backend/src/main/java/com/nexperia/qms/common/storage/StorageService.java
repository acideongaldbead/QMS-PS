package com.nexperia.qms.common.storage;

import org.springframework.core.io.Resource;

import java.io.InputStream;

/**
 * Where attachment bytes live. Phase 1 ships {@link LocalFsStorage} (a directory
 * beside the application); swapping in object storage later only means a new
 * implementation, because the database stores an opaque {@code storage_path} key.
 */
public interface StorageService {

    /**
     * Writes the stream under a caller-chosen key.
     *
     * @param objectKey relative key, e.g. {@code 2026/10/<uuid>.pdf}
     * @return the same key, for storing on the attachment row
     */
    String store(InputStream data, String objectKey);

    Resource load(String objectKey);

    void delete(String objectKey);

    boolean exists(String objectKey);
}
