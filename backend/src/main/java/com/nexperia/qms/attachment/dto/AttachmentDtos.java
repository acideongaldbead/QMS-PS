package com.nexperia.qms.attachment.dto;

import java.time.OffsetDateTime;

public final class AttachmentDtos {

    private AttachmentDtos() {
    }

    /** What the client sees. storage_path is deliberately not exposed. */
    public record AttachmentView(
            long attachmentId,
            String bizType,
            String bizTypeLabel,
            String bizId,
            String fileName,
            long fileSize,
            String fileType,
            String uploadedBy,
            String uploadedByName,
            OffsetDateTime uploadedAt,
            String downloadUrl) {
    }

    /** Upload result, including what the scanner said. */
    public record UploadResult(AttachmentView attachment, String scanResult) {
    }

    /**
     * The upload rules, served so the client can show the same limits the server
     * enforces instead of duplicating them.
     */
    public record UploadRules(java.util.List<String> allowedExtensions, long maxBytes) {
    }
}
