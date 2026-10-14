package com.nexperia.qms.common.numbering.mapper;

import org.apache.ibatis.annotations.Mapper;
import org.apache.ibatis.annotations.Param;
import org.apache.ibatis.annotations.Select;

/**
 * Calls the schema's own numbering function. It is an atomic
 * INSERT ... ON CONFLICT ... RETURNING on document_sequence, so concurrent
 * registrations cannot collide and no application-side lock is needed.
 */
@Mapper
public interface SequenceMapper {

    @Select("SELECT next_document_no(#{prefix}, #{biz}, #{width})")
    String next(@Param("prefix") String prefix, @Param("biz") String biz, @Param("width") int width);
}
