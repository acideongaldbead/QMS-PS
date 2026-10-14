package com.nexperia.qms.attachment;

import com.nexperia.qms.attachment.dto.AttachmentDtos;
import com.nexperia.qms.common.storage.FileValidator;
import org.springframework.core.io.Resource;
import org.springframework.http.ContentDisposition;
import org.springframework.http.HttpHeaders;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.web.bind.annotation.DeleteMapping;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;
import org.springframework.web.multipart.MultipartFile;

import java.nio.charset.StandardCharsets;
import java.util.List;

@RestController
@RequestMapping("/api/attachments")
public class AttachmentController {

    /**
     * Attaching a file means editing the record it belongs to, so the permission
     * is "may edit any of the things files attach to" rather than a separate
     * attachment permission.
     */
    private static final String MAY_ATTACH = "hasAnyAuthority("
            + "'complaint:edit','sample:edit','verify:edit','containment:edit',"
            + "'rootcause:edit','action:edit','prevention:edit','report:edit',"
            + "'knowledge:manage')";

    private final AttachmentService attachmentService;
    private final FileValidator fileValidator;

    public AttachmentController(AttachmentService attachmentService, FileValidator fileValidator) {
        this.attachmentService = attachmentService;
        this.fileValidator = fileValidator;
    }

    /** The whitelist and size ceiling, so the UI can state them without guessing. */
    @GetMapping("/rules")
    @PreAuthorize("hasAuthority('complaint:view')")
    public AttachmentDtos.UploadRules rules() {
        return new AttachmentDtos.UploadRules(
                fileValidator.allowedExtensions().stream().sorted().toList(),
                fileValidator.maxBytes());
    }

    @PostMapping
    @PreAuthorize(MAY_ATTACH)
    public AttachmentDtos.UploadResult upload(@RequestParam("file") MultipartFile file,
                                              @RequestParam("bizType") String bizType,
                                              @RequestParam("bizId") String bizId) {
        return attachmentService.upload(bizType, bizId, file);
    }

    @GetMapping
    @PreAuthorize("hasAuthority('complaint:view')")
    public List<AttachmentDtos.AttachmentView> list(@RequestParam("bizType") String bizType,
                                                    @RequestParam("bizId") String bizId) {
        return attachmentService.list(bizType, bizId);
    }

    /**
     * Streams the file. The client never learns a storage path: it asks for an
     * attachment id and the server resolves the bytes.
     */
    @GetMapping("/{attachmentId}/download")
    @PreAuthorize("hasAuthority('complaint:view')")
    public ResponseEntity<Resource> download(@PathVariable long attachmentId) {
        var downloaded = attachmentService.download(attachmentId);
        Attachment attachment = downloaded.attachment();
        Resource resource = downloaded.resource();

        // The original name may be Chinese, so the plain filename is an ASCII
        // fallback and filename* carries the real one (RFC 5987).
        String asciiFallback = attachment.getFileName().replaceAll("[^\\x20-\\x7E]", "_");
        ContentDisposition disposition = ContentDisposition.attachment()
                .filename(asciiFallback, StandardCharsets.UTF_8)
                .build();

        MediaType mediaType;
        try {
            mediaType = MediaType.parseMediaType(attachment.getFileType());
        } catch (RuntimeException e) {
            mediaType = MediaType.APPLICATION_OCTET_STREAM;
        }

        return ResponseEntity.ok()
                .contentType(mediaType)
                .contentLength(attachment.getFileSize())
                .header(HttpHeaders.CONTENT_DISPOSITION, disposition.toString())
                .body(resource);
    }

    @DeleteMapping("/{attachmentId}")
    @PreAuthorize(MAY_ATTACH)
    public void delete(@PathVariable long attachmentId) {
        attachmentService.delete(attachmentId);
    }
}
