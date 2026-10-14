package com.nexperia.qms.common.storage;

import org.apache.tika.Tika;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Component;

import java.io.IOException;
import java.io.InputStream;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.Set;

/**
 * Enforces requirement Q-15 / NFR-15: a single file of at most 50 MB from the
 * configured whitelist (`qms.upload.allowed-extensions`) - images, Office
 * documents (Word, Excel, PowerPoint), archives and mp4.
 *
 * The extension alone is easy to forge, so the file's real content type is sniffed
 * with Apache Tika and checked too. The decisive check is the deny list: whatever
 * the name says, a detected executable or script is refused. The per-extension
 * accept list then catches an obvious mismatch, and an Office package that carries
 * a VBA project is refused as well - `carriesVbaProject` explains why the content
 * type alone cannot answer that last question.
 */
@Component
public class FileValidator {

    private static final Logger log = LoggerFactory.getLogger(FileValidator.class);

    /** Refused no matter what the file is named. */
    private static final Set<String> DENIED_CONTENT_TYPES = Set.of(
            "application/x-dosexec",
            "application/x-msdownload",
            "application/x-msdos-program",
            "application/x-msi",
            "application/x-executable",
            "application/x-sharedlib",
            "application/x-mach-binary",
            "application/x-elf",
            "application/java-archive",
            "text/x-shellscript",
            "text/x-script.python",
            "text/x-python",
            "text/x-perl",
            "application/x-httpd-php",
            "application/x-ruby",
            "application/x-sh");

    /**
     * What a file with this extension is allowed to actually be. Several entries
     * list more than one type because producers and detectors legitimately differ:
     * a JPEG may be reported as image/jpg, the OOXML documents (docx/xlsx/pptx) are
     * ZIP containers and are sometimes reported as such, and the legacy Office
     * formats (doc/xls/ppt) are OLE2 containers that Tika may label with its
     * generic {@code application/x-tika-msoffice}.
     *
     * Map.ofEntries rather than Map.of: the latter tops out at ten pairs.
     */
    private static final Map<String, Set<String>> ACCEPTED_BY_EXTENSION = Map.ofEntries(
            Map.entry("jpg", Set.of("image/jpeg", "image/jpg")),
            Map.entry("jpeg", Set.of("image/jpeg", "image/jpg")),
            Map.entry("png", Set.of("image/png")),
            Map.entry("pdf", Set.of("application/pdf")),
            Map.entry("mp4", Set.of("video/mp4", "application/mp4")),
            Map.entry("zip", Set.of("application/zip", "application/x-zip", "application/x-zip-compressed")),
            Map.entry("doc", Set.of("application/msword", "application/x-tika-msoffice")),
            Map.entry("docx", Set.of(
                    "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
                    "application/x-tika-ooxml",
                    "application/zip")),
            Map.entry("xls", Set.of("application/vnd.ms-excel", "application/x-tika-msoffice")),
            Map.entry("xlsx", Set.of(
                    "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
                    "application/x-tika-ooxml",
                    "application/zip")),
            Map.entry("ppt", Set.of("application/vnd.ms-powerpoint", "application/x-tika-msoffice")),
            Map.entry("pptx", Set.of(
                    "application/vnd.openxmlformats-officedocument.presentationml.presentation",
                    "application/x-tika-ooxml",
                    "application/zip")));

    /** The OOXML extensions, whose packages are inspected for embedded macros. */
    private static final Set<String> OOXML_EXTENSIONS = Set.of("docx", "xlsx", "pptx");

    /** The part an Office package carries its VBA project in. */
    private static final String VBA_PART_SUFFIX = "vbaProject.bin";

    private final Tika tika = new Tika();
    private final Set<String> allowedExtensions;
    private final long maxBytes;

    public FileValidator(UploadProperties properties) {
        this.allowedExtensions = properties.getAllowedExtensions().stream()
                .map(e -> e.toLowerCase(Locale.ROOT).replace(".", "").trim())
                .collect(java.util.stream.Collectors.toUnmodifiableSet());
        this.maxBytes = properties.getMaxBytes();
    }

    /**
     * @param originalName the name the user uploaded, used only for the extension
     * @param size         declared size, checked before anything is written
     * @param content      the bytes on disk, sniffed for their real type
     */
    public ValidatedFile validate(String originalName, long size, Path content) {
        if (originalName == null || originalName.isBlank()) {
            throw new IllegalArgumentException("未提供文件名");
        }
        if (size <= 0) {
            throw new IllegalArgumentException("文件内容为空");
        }
        if (size > maxBytes) {
            throw new IllegalArgumentException(
                    "文件超过上限 " + (maxBytes / 1024 / 1024) + "MB，当前 " + (size / 1024 / 1024) + "MB");
        }

        String extension = extensionOf(originalName);
        if (!allowedExtensions.contains(extension)) {
            throw new IllegalArgumentException(
                    "不支持的文件类型 ." + extension + "，仅允许：" + String.join(" / ", allowedExtensions));
        }

        String detected = detect(content, originalName);
        if (DENIED_CONTENT_TYPES.contains(detected)) {
            log.warn("Refused upload '{}': content detected as {}", originalName, detected);
            throw new IllegalArgumentException(
                    "文件内容被识别为可执行程序或脚本（" + detected + "），已拒绝上传");
        }

        Set<String> accepted = ACCEPTED_BY_EXTENSION.get(extension);
        if (accepted != null && !accepted.contains(detected)) {
            log.warn("Refused upload '{}': extension .{} but content detected as {}",
                    originalName, extension, detected);
            throw new IllegalArgumentException(
                    "文件内容（" + detected + "）与扩展名 ." + extension + " 不一致，已拒绝上传");
        }

        if (OOXML_EXTENSIONS.contains(extension) && carriesVbaProject(content)) {
            log.warn("Refused upload '{}': the package carries {}", originalName, VBA_PART_SUFFIX);
            throw new IllegalArgumentException(
                    "文件中包含 VBA 宏（" + VBA_PART_SUFFIX + "），系统不接受宏文档，已拒绝上传");
        }

        return new ValidatedFile(originalName, extension, detected, size);
    }

    /**
     * Whether an Office Open XML package carries a VBA project.
     *
     * The content-type check alone cannot answer this: Tika names an OOXML package
     * after its main part (ppt/presentation.xml and friends), so a macro-enabled
     * document renamed to the macro-free extension is still detected as the
     * macro-free type. The package's own entry list is the reliable signal, and it
     * costs one zip listing.
     */
    private boolean carriesVbaProject(Path content) {
        try (java.util.zip.ZipFile zip = new java.util.zip.ZipFile(content.toFile())) {
            return zip.stream().anyMatch(entry -> entry.getName().endsWith(VBA_PART_SUFFIX));
        } catch (IOException e) {
            // Not a readable zip. The content-type gate above has already refused
            // anything that is not an OOXML package.
            return false;
        }
    }

    /** The extension without the dot, lower case. */
    public static String extensionOf(String fileName) {
        int dot = fileName.lastIndexOf('.');
        return dot < 0 ? "" : fileName.substring(dot + 1).toLowerCase(Locale.ROOT);
    }

    /**
     * Content-first detection: Tika inspects the stream's magic bytes and only
     * falls back to the file name when the content is ambiguous. That is why an
     * executable renamed to .pdf is still identified as an executable.
     */
    private String detect(Path content, String originalName) {
        try (InputStream in = Files.newInputStream(content)) {
            return tika.detect(in, originalName);
        } catch (IOException e) {
            // Failing open would accept a file we could not inspect, so fail closed.
            throw new IllegalStateException("无法识别文件类型，已拒绝上传", e);
        }
    }

    public long maxBytes() {
        return maxBytes;
    }

    public Set<String> allowedExtensions() {
        return allowedExtensions;
    }

    /** A file that passed every check. */
    public record ValidatedFile(String originalName, String extension, String contentType, long size) {
    }
}
