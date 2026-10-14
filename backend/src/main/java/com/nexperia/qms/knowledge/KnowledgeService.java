package com.nexperia.qms.knowledge;

import com.nexperia.qms.common.audit.AuditActions;
import com.nexperia.qms.common.audit.AuditLogService;
import com.nexperia.qms.common.exception.NotFoundException;
import com.nexperia.qms.common.security.CurrentUserContext;
import com.nexperia.qms.knowledge.dto.KnowledgeDtos;
import com.nexperia.qms.knowledge.mapper.KnowledgeMapper;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.util.List;

/**
 * The knowledge centre (requirement 3.11).
 *
 * Reading is open to anyone holding {@code knowledge:view}; maintenance
 * (create / edit / delete / attaching the document file) is {@code knowledge:manage}
 * and, by the prototype's rule, the administrator.
 *
 * Creating an entry publishes it immediately: the draft and archived statuses the
 * baseline seeds are not surfaced in this phase, so nothing here ever writes one.
 * Entries are soft-deleted, which also releases their document number because the
 * uniqueness index only covers live rows.
 */
@Service
public class KnowledgeService {

    static final String BIZ_TYPE = "KnowledgeArticle";
    private static final String PUBLISHED = "ARTICLE_PUBLISHED";

    private final KnowledgeMapper knowledgeMapper;
    private final AuditLogService auditLogService;

    public KnowledgeService(KnowledgeMapper knowledgeMapper, AuditLogService auditLogService) {
        this.knowledgeMapper = knowledgeMapper;
        this.auditLogService = auditLogService;
    }

    @Transactional(readOnly = true)
    public List<KnowledgeDtos.ArticleView> list(String category, String keyword) {
        return knowledgeMapper.findArticles(null, trimToNull(category), trimToNull(keyword));
    }

    /**
     * Per-category counts plus the total, for the sidebar. Categories holding no
     * documents are absent here on purpose: the UI renders the dictionary, so an
     * empty category still appears with a zero.
     */
    @Transactional(readOnly = true)
    public KnowledgeDtos.KnowledgeSummary summary() {
        List<KnowledgeDtos.CategoryCount> counts = knowledgeMapper.countByCategory();
        long total = counts.stream().mapToLong(KnowledgeDtos.CategoryCount::total).sum();
        return new KnowledgeDtos.KnowledgeSummary(total, counts);
    }

    @Transactional(readOnly = true)
    public KnowledgeDtos.ArticleView get(long articleId) {
        List<KnowledgeDtos.ArticleView> found = knowledgeMapper.findArticles(articleId, null, null);
        if (found.isEmpty()) {
            throw new NotFoundException("知识文档不存在：" + articleId);
        }
        return found.get(0);
    }

    @Transactional
    public KnowledgeDtos.ArticleView create(KnowledgeDtos.SaveRequest request) {
        requireCategory(request.category());
        String docCode = trimToNull(request.docCode());
        requireDocCodeFree(docCode, null);

        KnowledgeArticle article = new KnowledgeArticle();
        article.setTitle(request.title().trim());
        article.setTitleEn(trimToNull(request.titleEn()));
        article.setCategory(request.category());
        article.setDocCode(docCode);
        article.setVersion(trimToNull(request.version()));
        article.setSummary(trimToNull(request.summary()));
        article.setContent(trimToNull(request.content()));
        article.setStatusCode(PUBLISHED);
        knowledgeMapper.insert(article);

        auditLogService.record(AuditActions.CREATE, BIZ_TYPE, String.valueOf(article.getArticleId()),
                "新增知识文档：" + article.getTitle());
        return get(article.getArticleId());
    }

    @Transactional
    public KnowledgeDtos.ArticleView update(long articleId, KnowledgeDtos.SaveRequest request) {
        KnowledgeArticle before = requireArticle(articleId);
        requireCategory(request.category());
        String docCode = trimToNull(request.docCode());
        requireDocCodeFree(docCode, articleId);

        String title = request.title().trim();
        String version = trimToNull(request.version());
        knowledgeMapper.updateArticle(articleId, title, trimToNull(request.titleEn()),
                request.category(), docCode, version, trimToNull(request.summary()),
                trimToNull(request.content()), CurrentUserContext.employeeId());

        auditLogService.recordValueChange(AuditActions.UPDATE, BIZ_TYPE, String.valueOf(articleId),
                describe(before), describe(title, request.category(), docCode, version));
        return get(articleId);
    }

    @Transactional
    public void delete(long articleId) {
        KnowledgeArticle before = requireArticle(articleId);
        knowledgeMapper.deleteById(articleId);
        auditLogService.record(AuditActions.DELETE, BIZ_TYPE, String.valueOf(articleId),
                "删除知识文档：" + before.getTitle());
    }

    private KnowledgeArticle requireArticle(long articleId) {
        KnowledgeArticle article = knowledgeMapper.selectById(articleId);
        if (article == null) {
            throw new NotFoundException("知识文档不存在：" + articleId);
        }
        return article;
    }

    private void requireCategory(String category) {
        if (knowledgeMapper.countCategory(category) == 0) {
            throw new IllegalArgumentException("文档分类不存在：" + category);
        }
    }

    /**
     * A document number, when supplied, must be unique. The partial unique index
     * is the backstop; this check exists so the caller gets 409 with the number in
     * the message rather than a translated constraint violation.
     */
    private void requireDocCodeFree(String docCode, Long excludeId) {
        if (docCode != null && knowledgeMapper.countByDocCode(docCode, excludeId) > 0) {
            throw new IllegalStateException("文档编号已存在：" + docCode);
        }
    }

    private String describe(KnowledgeArticle article) {
        return describe(article.getTitle(), article.getCategory(), article.getDocCode(), article.getVersion());
    }

    private String describe(String title, String category, String docCode, String version) {
        return "编号=" + orDash(docCode) + "；标题=" + title + "；分类=" + category + "；版本=" + orDash(version);
    }

    private String orDash(String value) {
        return value == null ? "-" : value;
    }

    private String trimToNull(String value) {
        if (value == null) {
            return null;
        }
        String trimmed = value.trim();
        return trimmed.isEmpty() ? null : trimmed;
    }
}
