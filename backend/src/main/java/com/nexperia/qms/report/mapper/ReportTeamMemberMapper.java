package com.nexperia.qms.report.mapper;

import com.baomidou.mybatisplus.core.mapper.BaseMapper;
import com.nexperia.qms.report.ReportTeamMember;
import org.apache.ibatis.annotations.Mapper;
import org.apache.ibatis.annotations.Param;
import org.apache.ibatis.annotations.Select;

import java.util.List;

@Mapper
public interface ReportTeamMemberMapper extends BaseMapper<ReportTeamMember> {

    @Select("""
            SELECT * FROM report_team_member
             WHERE report_id = #{reportId} AND is_deleted = false
             ORDER BY sort_order, team_member_id
            """)
    List<ReportTeamMember> findByReport(@Param("reportId") String reportId);
}
