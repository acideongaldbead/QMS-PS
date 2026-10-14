package com.nexperia.qms.knowledge.mapper;

import com.baomidou.mybatisplus.core.mapper.BaseMapper;
import com.nexperia.qms.knowledge.KnowledgeArticle;
import com.nexperia.qms.knowledge.dto.KnowledgeDtos;
import org.apache.ibatis.annotations.Mapper;
import org.apache.ibatis.annotations.Param;
import org.apache.ibatis.annotations.Select;
import org.apache.ibatis.annotations.Update;

import java.util.List;

@Mapper
public interface KnowledgeMapper extends BaseMapper<KnowledgeArticle> {

    /**
     * The document list, or a single document when {@code articleId} is given.
     *
     * The select list order must match the components of {@link KnowledgeDtos.ArticleView}-
     * MyBatis maps a record through its constructor, by column position rather than
     * by name. Both sides are numbered so a new column cannot silently shift the rest.
     *
     * The attachment is fetched with a LATERAL join because a document keeps every
     * upload it ever had; only the newest one is shown in the row.
     */
    @Select("""
            <script>
            SELECT a.article_id      AS articleId,       --  1
                   a.doc_code        AS docCode,         --  2
                   a.title           AS title,           --  3
                   a.title_en        AS titleEn,         --  4
                   a.category        AS category,        --  5
                   m.name_cn         AS categoryName,    --  6
                   m.name_en         AS categoryNameEn,  --  7
                   a.version         AS version,         --  8
                   a.summary         AS summary,         --  9
                   a.content         AS content,         -- 10
                   e.name            AS maintainerName,  -- 11
                   a.updated_at      AS updatedAt,           -- 12
                   att.attachment_id AS latestAttachmentId,  -- 13
                   att.file_name     AS latestFileName,      -- 14
                   att.file_size     AS latestFileSize,      -- 15
                   att.file_type     AS latestFileType       -- 16
              FROM knowledge_article a
              LEFT JOIN master_data_item m ON m.code = a.category AND m.is_deleted = false
              LEFT JOIN employee e         ON e.employee_id = a.updated_by
              LEFT JOIN LATERAL (
                    SELECT f.attachment_id, f.file_name, f.file_size, f.file_type
                      FROM attachment f
                     WHERE f.biz_type = 'KnowledgeArticle'
                       AND f.biz_id = a.article_id::text
                       AND f.is_deleted = false
                     ORDER BY f.uploaded_at DESC, f.attachment_id DESC
                     LIMIT 1
                   ) att ON true
             WHERE a.is_deleted = false
               AND a.status_code = 'ARTICLE_PUBLISHED'
            <if test="articleId != null">
               AND a.article_id = #{articleId}
            </if>
            <if test="category != null and category != ''">
               AND a.category = #{category}
            </if>
            <if test="keyword != null and keyword != ''">
               AND (a.doc_code ILIKE '%' || #{keyword} || '%'
                 OR a.title    ILIKE '%' || #{keyword} || '%'
                 OR a.title_en ILIKE '%' || #{keyword} || '%'
                 OR a.summary  ILIKE '%' || #{keyword} || '%')
            </if>
             ORDER BY m.sort_order NULLS LAST, a.doc_code NULLS LAST, a.article_id
            </script>
            """)
    List<KnowledgeDtos.ArticleView> findArticles(@Param("articleId") Long articleId,
                                                 @Param("category") String category,
                                                 @Param("keyword") String keyword);

    /** How many live documents each category holds, for the sidebar. */
    @Select("""
            SELECT a.category AS category, count(*) AS total
              FROM knowledge_article a
             WHERE a.is_deleted = false
               AND a.status_code = 'ARTICLE_PUBLISHED'
             GROUP BY a.category
            """)
    List<KnowledgeDtos.CategoryCount> countByCategory();

    /**
     * An explicit UPDATE rather than MyBatis-Plus {@code updateById}: the latter
     * skips null fields, so clearing an optional column would report success while
     * leaving the old value in the row.
     */
    @Update("""
            UPDATE knowledge_article
               SET title      = #{title},
                   title_en   = #{titleEn},
                   category   = #{category},
                   doc_code   = #{docCode},
                   version    = #{version},
                   summary    = #{summary},
                   content    = #{content},
                   updated_by = #{updatedBy}
             WHERE article_id = #{articleId} AND is_deleted = false
            """)
    int updateArticle(@Param("articleId") long articleId,
                      @Param("title") String title,
                      @Param("titleEn") String titleEn,
                      @Param("category") String category,
                      @Param("docCode") String docCode,
                      @Param("version") String version,
                      @Param("summary") String summary,
                      @Param("content") String content,
                      @Param("updatedBy") String updatedBy);

    /** Duplicate document numbers are refused, so this counts the others. */
    @Select("""
            <script>
            SELECT count(*) FROM knowledge_article
             WHERE is_deleted = false AND doc_code = #{docCode}
            <if test="excludeId != null">
               AND article_id &lt;&gt; #{excludeId}
            </if>
            </script>
            """)
    int countByDocCode(@Param("docCode") String docCode, @Param("excludeId") Long excludeId);

    /** The category must be a live entry of the knowledge_category dictionary. */
    @Select("""
            SELECT count(*) FROM master_data_item
             WHERE md_type = 'knowledge_category'
               AND code = #{code}
               AND is_active = true
               AND is_deleted = false
            """)
    int countCategory(@Param("code") String code);
}
