package com.nexperia.qms.complaint;

import com.nexperia.qms.complaint.dto.ComplaintRequests;
import com.nexperia.qms.complaint.mapper.ReferenceMapper;
import org.springframework.stereotype.Component;

import java.util.ArrayList;
import java.util.HashMap;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Map;
import java.util.Objects;
import java.util.Set;

/**
 * Checks that three failure type codes form a chain (L2 under L1, L3 under L2),
 * which requirement 3.3 demands.
 *
 * A foreign key can prove each code exists but not that the three relate, so this
 * has to live in application code. It is a separate component because registering
 * a complaint, editing a sample and recording a D2 verification result all apply
 * the same rule -- hence the neutral {@link Codes} form rather than anything
 * shaped like one particular screen.
 */
@Component
public class FailureTypeChainValidator {

    private final ReferenceMapper referenceMapper;

    public FailureTypeChainValidator(ReferenceMapper referenceMapper) {
        this.referenceMapper = referenceMapper;
    }

    /** One L1/L2/L3 triple, in whatever business context it appears. */
    public record Codes(String l1, String l2, String l3) {
    }

    public void validate(List<ComplaintRequests.Sample> samples, List<String> errors) {
        if (samples == null || samples.isEmpty()) {
            return;
        }
        List<Codes> triples = new ArrayList<>();
        for (ComplaintRequests.Sample sample : samples) {
            triples.add(new Codes(
                    sample.failureTypeL1Code(), sample.failureTypeL2Code(), sample.failureTypeL3Code()));
        }
        validateTriples(triples, errors);
    }

    /**
     * Appends every problem it finds to {@code errors} rather than throwing, so
     * the caller can report all issues of a request at once.
     */
    public void validateTriples(List<Codes> triples, List<String> errors) {
        if (triples == null || triples.isEmpty()) {
            return;
        }

        Set<String> codes = new LinkedHashSet<>();
        for (Codes triple : triples) {
            addIfPresent(codes, triple.l1());
            addIfPresent(codes, triple.l2());
            addIfPresent(codes, triple.l3());
        }
        if (codes.isEmpty()) {
            return;
        }

        Map<String, ReferenceMapper.FailureTypeHierarchy> byCode = new HashMap<>();
        for (ReferenceMapper.FailureTypeHierarchy node : referenceMapper.findFailureTypeHierarchy(codes)) {
            byCode.put(node.code(), node);
        }

        for (Codes triple : triples) {
            String l1 = triple.l1();
            String l2 = triple.l2();
            String l3 = triple.l3();

            if (l2 != null && l1 == null) {
                errors.add("选择了二级失效类型但未选择一级失效类型");
            }
            if (l3 != null && l2 == null) {
                errors.add("选择了三级失效类型但未选择二级失效类型");
            }
            requireLevel(byCode, l1, 1, "一级", errors);
            requireLevel(byCode, l2, 2, "二级", errors);
            requireLevel(byCode, l3, 3, "三级", errors);

            if (l1 != null && l2 != null) {
                var node = byCode.get(l2);
                if (node != null && !Objects.equals(node.parentcode(), l1)) {
                    errors.add("二级失效类型 " + l2 + " 不属于所选一级失效类型 " + l1);
                }
            }
            if (l2 != null && l3 != null) {
                var node = byCode.get(l3);
                if (node != null && !Objects.equals(node.parentcode(), l2)) {
                    errors.add("三级失效类型 " + l3 + " 不属于所选二级失效类型 " + l2);
                }
            }
        }
    }

    private void requireLevel(Map<String, ReferenceMapper.FailureTypeHierarchy> byCode,
                              String code, int expectedLevel, String label, List<String> errors) {
        if (code == null || code.isBlank()) {
            return;
        }
        var node = byCode.get(code);
        if (node == null) {
            errors.add(label + "失效类型不存在或已停用：" + code);
        } else if (node.levelno() != expectedLevel) {
            errors.add(label + "失效类型编码 " + code + " 的层级不正确");
        }
    }

    private static void addIfPresent(Set<String> target, String value) {
        if (value != null && !value.isBlank()) {
            target.add(value);
        }
    }
}
