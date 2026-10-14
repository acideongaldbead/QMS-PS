package com.nexperia.qms.attachment;

import com.nexperia.qms.attachment.dto.AttachmentDtos;
import com.nexperia.qms.attachment.mapper.AttachmentMapper;
import com.nexperia.qms.common.audit.AuditActions;
import com.nexperia.qms.common.audit.AuditLogService;
import com.nexperia.qms.common.exception.NotFoundException;
import com.nexperia.qms.common.security.CurrentUserContext;
import com.nexperia.qms.common.storage.AntivirusScanner;
import com.nexperia.qms.common.storage.FileValidator;
import com.nexperia.qms.common.storage.StorageService;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.core.io.Resource;
import org.springframework.security.access.AccessDeniedException;
import org.springframework.security.core.GrantedAuthority;
import org.springframework.security.core.context.SecurityContextHolder;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.multipart.MultipartFile;

import java.io.IOException;
import java.io.InputStream;
import java.nio.file.Files;
import java.nio.file.Path;
import java.time.LocalDate;
import java.time.OffsetDateTime;
import java.time.format.DateTimeFormatter;
import java.util.List;
import java.util.UUID;

/**
 * Upload, list, download and remove attachments.
 *
 * Order of operations on upload matters: the bytes are written to a temporary file
 * first, then validated by content, then scanned, and only then promoted into
 * storage and recorded. Nothing unscanned ever reaches the attachment directory,
 * which is what requirement Q-15 asks for.
 */
@Service
public class AttachmentService {

    private static final Logger log = LoggerFactory.getLogger(AttachmentService.class);

    private static final DateTimeFormatter MONTH_PATH = DateTimeFormatter.ofPattern("yyyy/MM");

    private final AttachmentMapper attachmentMapper;
    private final StorageService storageService;
    private final FileValidator fileValidator;
    private final AntivirusScanner antivirusScanner;
    private final AuditLogService auditLogService;

    public AttachmentService(AttachmentMapper attachmentMapper,
                             StorageService storageService,
                             FileValidator fileValidator,
                             AntivirusScanner antivirusScanner,
                             AuditLogService auditLogService) {
        this.attachmentMapper = attachmentMapper;
        this.storageService = storageService;
        this.fileValidator = fileValidator;
        this.antivirusScanner = antivirusScanner;
        this.auditLogService = auditLogService;
    }

    @Transactional
    public AttachmentDtos.UploadResult upload(String bizType, String bizId, MultipartFile file) {
        requireSupportedBiz(bizType);
        requireWritePermission(bizType);
        if (attachmentMapper.countParent(bizType, bizId) == 0) {
            throw new NotFoundException(
                    AttachmentBizType.label(bizType) + "不存在：" + bizId);
        }

        String originalName = file.getOriginalFilename();
        Path tempDir = Path.of(System.getProperty("java.io.tmpdir"), "qms-upload");
        Path temp = null;
        try {
            Files.createDirectories(tempDir);
            temp = Files.createTempFile(tempDir, "up-", ".part");
            try (InputStream in = file.getInputStream()) {
                Files.copy(in, temp, java.nio.file.StandardCopyOption.REPLACE_EXISTING);
            }

            FileValidator.ValidatedFile validated =
                    fileValidator.validate(originalName, file.getSize(), temp);

            AntivirusScanner.ScanResult scan = antivirusScanner.scan(temp);
            if (!scan.clean()) {
                throw new IllegalArgumentException("文件未通过安全扫描，已拒绝保存：" + scan.detail());
            }

            String objectKey = buildObjectKey(validated.extension());
            try (InputStream in = Files.newInputStream(temp)) {
                storageService.store(in, objectKey);
            }

            Attachment entity = new Attachment();
            entity.setBizType(bizType);
            entity.setBizId(bizId);
            entity.setFileName(validated.originalName());
            entity.setFileSize(validated.size());
            entity.setFileType(validated.contentType());
            entity.setStoragePath(objectKey);
            entity.setUploadedBy(CurrentUserContext.employeeId());
            entity.setUploadedAt(OffsetDateTime.now());
            attachmentMapper.insert(entity);

            auditLogService.record(AuditActions.CREATE, "Attachment", bizId,
                    "上传附件：" + validated.originalName() + "（" + validated.contentType()
                            + "，" + validated.size() + " 字节），扫描：" + scan.detail());

            return new AttachmentDtos.UploadResult(
                    toView(entity, CurrentUserContext.employeeId(), null), scan.detail());
        } catch (IllegalArgumentException | IllegalStateException e) {
            // Every refusal is worth a durable record -- a file renamed to slip past
            // the whitelist is precisely what a security review looks for. The
            // independent transaction keeps the entry after this one rolls back.
            auditLogService.recordRegardlessOfOutcome(AuditActions.UPLOAD_REJECTED, "Attachment", bizId,
                    "附件被拒绝：" + originalName + "，" + e.getMessage());
            throw e;
        } catch (IOException e) {
            throw new IllegalStateException("附件上传失败", e);
        } finally {
            if (temp != null) {
                try {
                    Files.deleteIfExists(temp);
                } catch (IOException e) {
                    log.warn("Could not remove upload temp file {}", temp, e);
                }
            }
        }
    }

    @Transactional(readOnly = true)
    public List<AttachmentDtos.AttachmentView> list(String bizType, String bizId) {
        requireSupportedBiz(bizType);
        return attachmentMapper.findByBiz(bizType, bizId).stream()
                .map(row -> new AttachmentDtos.AttachmentView(
                        row.attachmentId(), row.bizType(), AttachmentBizType.label(row.bizType()),
                        row.bizId(), row.fileName(), row.fileSize(), row.fileType(),
                        row.uploadedBy(), row.uploadedByName(), row.uploadedAt(),
                        "/api/attachments/" + row.attachmentId() + "/download"))
                .toList();
    }

    /** Returns the row plus the bytes, so the controller can stream them. */
    @Transactional(readOnly = true)
    public DownloadedAttachment download(long attachmentId) {
        Attachment entity = attachmentMapper.selectById(attachmentId);
        if (entity == null) {
            throw new NotFoundException("附件不存在：" + attachmentId);
        }
        Resource resource = storageService.load(entity.getStoragePath());
        return new DownloadedAttachment(entity, resource);
    }

    /**
     * Soft-deletes the row and records the action.
     *
     * The stored file is deliberately left on disk: deleting from two places
     * cannot be made atomic, and keeping the bytes means a review can still see
     * what was attached. A retention job for soft-deleted files is an operational
     * task, noted as a known gap.
     */
    @Transactional
    public void delete(long attachmentId) {
        Attachment entity = attachmentMapper.selectById(attachmentId);
        if (entity == null) {
            throw new NotFoundException("附件不存在：" + attachmentId);
        }
        requireWritePermission(entity.getBizType());
        attachmentMapper.deleteById(attachmentId);
        auditLogService.record(AuditActions.DELETE, "Attachment", entity.getBizId(),
                "删除附件：" + entity.getFileName() + "（记录 " + attachmentId + "）");
    }

    private void requireSupportedBiz(String bizType) {
        if (!AttachmentBizType.isKnown(bizType)) {
            throw new IllegalArgumentException("不支持的业务类型：" + bizType);
        }
    }

    /**
     * The controller's MAY_ATTACH is a flat hasAnyAuthority over every edit code,
     * which is too wide on its own: it would let, say, an engineer holding
     * {@code rootcause:edit} attach a file to a knowledge document. The permission
     * that counts is the one for the record type being written.
     *
     * Runs after the supported-type check so an unknown type still answers 400
     * rather than 403, and before the parent lookup so an unauthorised caller
     * cannot use the endpoint to probe which ids exist.
     */
    private void requireWritePermission(String bizType) {
        var authentication = SecurityContextHolder.getContext().getAuthentication();
        boolean allowed = authentication != null
                && authentication.getAuthorities().stream()
                        .map(GrantedAuthority::getAuthority)
                        .anyMatch(AttachmentBizType.writePermissions(bizType)::contains);
        if (!allowed) {
            throw new AccessDeniedException(
                    AttachmentBizType.label(bizType) + "的附件只能由有相应权限的人维护");
        }
    }

    private String buildObjectKey(String extension) {
        String month = LocalDate.now().format(MONTH_PATH);
        String id = UUID.randomUUID().toString().replace("-", "");
        return month + "/" + id + (extension.isEmpty() ? "" : "." + extension);
    }

    private AttachmentDtos.AttachmentView toView(Attachment entity, String uploaderId, String uploaderName) {
        return new AttachmentDtos.AttachmentView(
                entity.getAttachmentId(), entity.getBizType(),
                AttachmentBizType.label(entity.getBizType()), entity.getBizId(),
                entity.getFileName(), entity.getFileSize(), entity.getFileType(),
                uploaderId, uploaderName, entity.getUploadedAt(),
                "/api/attachments/" + entity.getAttachmentId() + "/download");
    }

    public record DownloadedAttachment(Attachment attachment, Resource resource) {
    }
}
