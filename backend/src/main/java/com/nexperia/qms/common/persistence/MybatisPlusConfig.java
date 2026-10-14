package com.nexperia.qms.common.persistence;

import com.baomidou.mybatisplus.annotation.DbType;
import com.baomidou.mybatisplus.extension.plugins.MybatisPlusInterceptor;
import com.baomidou.mybatisplus.extension.plugins.inner.PaginationInnerInterceptor;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;

/**
 * Pagination support for the read-heavy screens (the complaint ledger is the
 * first one). The interceptor only acts on methods that take an {@code IPage}
 * parameter, so the existing repositories are untouched.
 *
 * <p>The count-SQL rewrites are switched off per query (see
 * {@code ComplaintService.listLedger}): MyBatis-Plus otherwise tries to rewrite
 * the count statement with a SQL parser, dropping joins and replacing the select
 * list. The ledger query selects a function call and orders by expressions, the
 * exact shape those rewrites get wrong. Wrapping the original query as a subquery
 * costs a little more and is always right. Turn it off globally as well, so a
 * future paged query does not have to remember.
 */
@Configuration
public class MybatisPlusConfig {

    /** Ceiling for a single page, well above the largest page size the UI offers. */
    private static final long MAX_PAGE_SIZE = 500L;

    @Bean
    public MybatisPlusInterceptor mybatisPlusInterceptor() {
        PaginationInnerInterceptor pagination = new PaginationInnerInterceptor(DbType.POSTGRE_SQL);
        pagination.setOptimizeJoin(false);
        pagination.setMaxLimit(MAX_PAGE_SIZE);

        MybatisPlusInterceptor interceptor = new MybatisPlusInterceptor();
        interceptor.addInnerInterceptor(pagination);
        return interceptor;
    }
}
