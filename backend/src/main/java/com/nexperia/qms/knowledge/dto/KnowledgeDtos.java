package com.nexperia.qms.knowledge.dto;

import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Size;

import java.time.OffsetDateTime;
import java.util.List;

/**
 * Response and request shapes for the knowledge centre (requirement 3.11).
 * Grouped in one holder so the whole contract is visible in a single file.
 */
public final class KnowledgeDtos {

    private KnowledgeDtos() {
    }

    /**
     * One knowledge document, with its category names and its newest attachment
     * resolved so the list can render the row without extra calls.
     *
     * {@code categoryName} / {@code categoryNameEn} come from the dictionary row;
     * the UI picks the one matching the current language. The three
     * {@code latestFile*} fields are null when no document file has been uploaded.
     */
    public record ArticleView(
            Long articleId,
            String docCode,
            String title,
            String titleEn,
            String category,
            String categoryName,
            String categoryNameEn,
            String version,
            String summary,
            String content,
            String maintainerName,
            OffsetDateTime updatedAt,
            Long latestAttachmentId,
            String latestFileName,
            Long latestFileSize,
            String latestFileType) {
    }

    /** One row of the category filter, with how many documents it holds. */
    public record CategoryCount(String category, long total) {
    }

    /** Everything the sidebar needs: per-category counts plus the grand total. */
    public record KnowledgeSummary(long total, List<CategoryCount> categories) {
    }

    /** Create and update share one shape; the article id comes from the path. */
    public record SaveRequest(
            @NotBlank(message = "标题不能为空")
            @Size(max = 255, message = "标题不能超过 255 个字符")
            String title,
            @Size(max = 255, message = "英文标题不能超过 255 个字符")
            String titleEn,
            @NotBlank(message = "文档分类不能为空")
            String category,
            @Size(max = 32, message = "文档编号不能超过 32 个字符")
            String docCode,
            @Size(max = 16, message = "版本号不能超过 16 个字符")
            String version,
            @Size(max = 500, message = "描述不能超过 500 个字符")
            String summary,
            String content) {
    }
}
