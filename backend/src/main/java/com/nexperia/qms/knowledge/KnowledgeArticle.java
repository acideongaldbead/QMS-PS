package com.nexperia.qms.knowledge;

import com.baomidou.mybatisplus.annotation.IdType;
import com.baomidou.mybatisplus.annotation.TableId;
import com.baomidou.mybatisplus.annotation.TableName;
import com.nexperia.qms.common.persistence.BaseEntity;
import lombok.Data;
import lombok.EqualsAndHashCode;

/**
 * A knowledge-centre entry (requirement 3.11): a process document, an analysis
 * template, a training material or a user manual.
 *
 * The entry carries the metadata and the body text; the document file itself is a
 * row in the shared attachment table, reached through
 * {@code AttachmentBizType.KNOWLEDGE_ARTICLE}. That means "keeping history" needs
 * no version table: every upload stays in the attachment list, newest first.
 *
 * {@code category} holds a {@code master_data_item} code of type
 * {@code knowledge_category}, not free text.
 */
@Data
@EqualsAndHashCode(callSuper = true)
@TableName("knowledge_article")
public class KnowledgeArticle extends BaseEntity {

    @TableId(value = "article_id", type = IdType.AUTO)
    private Long articleId;

    private String title;

    /** English title, for the language switch (requirement 3.17). */
    private String titleEn;

    /** Business document number, e.g. XPR-0036. Unique among live rows; may be null. */
    private String docCode;

    /** master_data_item.code of type knowledge_category. */
    private String category;

    /** Free label such as V4.0, maintained by the administrator. */
    private String version;

    /** One-line description shown under the title in the list. */
    private String summary;

    /** Body text. File-based documents carry their content as an attachment. */
    private String content;

    /** ARTICLE_PUBLISHED for the entries this phase exposes. */
    private String statusCode;
}
