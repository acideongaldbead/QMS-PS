package com.nexperia.qms.knowledge;

import com.nexperia.qms.knowledge.dto.KnowledgeDtos;
import jakarta.validation.Valid;
import org.springframework.http.HttpStatus;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.web.bind.annotation.DeleteMapping;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.ResponseStatus;
import org.springframework.web.bind.annotation.RestController;

import java.util.List;

/**
 * The knowledge centre (requirement 3.11): process documents, analysis templates,
 * training materials and user manuals.
 *
 * Every role reads; only {@code knowledge:manage} (the administrator) maintains.
 * The document file is uploaded through the shared attachment API with
 * {@code bizType=KnowledgeArticle} and the article id as {@code bizId}.
 */
@RestController
@RequestMapping("/api/knowledge")
public class KnowledgeController {

    private static final String MAY_VIEW = "hasAuthority('knowledge:view')";
    private static final String MAY_MANAGE = "hasAuthority('knowledge:manage')";

    private final KnowledgeService knowledgeService;

    public KnowledgeController(KnowledgeService knowledgeService) {
        this.knowledgeService = knowledgeService;
    }

    @GetMapping("/articles")
    @PreAuthorize(MAY_VIEW)
    public List<KnowledgeDtos.ArticleView> list(
            @RequestParam(required = false) String category,
            @RequestParam(required = false) String keyword) {
        return knowledgeService.list(category, keyword);
    }

    /** Per-category document counts for the category filter. */
    @GetMapping("/summary")
    @PreAuthorize(MAY_VIEW)
    public KnowledgeDtos.KnowledgeSummary summary() {
        return knowledgeService.summary();
    }

    @GetMapping("/articles/{articleId}")
    @PreAuthorize(MAY_VIEW)
    public KnowledgeDtos.ArticleView get(@PathVariable long articleId) {
        return knowledgeService.get(articleId);
    }

    @PostMapping("/articles")
    @ResponseStatus(HttpStatus.CREATED)
    @PreAuthorize(MAY_MANAGE)
    public KnowledgeDtos.ArticleView create(@Valid @RequestBody KnowledgeDtos.SaveRequest request) {
        return knowledgeService.create(request);
    }

    @PutMapping("/articles/{articleId}")
    @PreAuthorize(MAY_MANAGE)
    public KnowledgeDtos.ArticleView update(@PathVariable long articleId,
                                            @Valid @RequestBody KnowledgeDtos.SaveRequest request) {
        return knowledgeService.update(articleId, request);
    }

    @DeleteMapping("/articles/{articleId}")
    @ResponseStatus(HttpStatus.NO_CONTENT)
    @PreAuthorize(MAY_MANAGE)
    public void delete(@PathVariable long articleId) {
        knowledgeService.delete(articleId);
    }
}
