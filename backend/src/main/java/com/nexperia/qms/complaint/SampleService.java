package com.nexperia.qms.complaint;

import com.nexperia.qms.common.audit.AuditActions;
import com.nexperia.qms.common.audit.AuditLogService;
import com.nexperia.qms.common.exception.NotFoundException;
import com.nexperia.qms.common.numbering.DocumentNumberService;
import com.nexperia.qms.complaint.dto.ComplaintRequests;
import com.nexperia.qms.complaint.mapper.ComplaintMapper;
import com.nexperia.qms.complaint.mapper.SampleMapper;
import com.nexperia.qms.logistics.mapper.ShipmentSampleMapper;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.util.ArrayList;
import java.util.List;

/**
 * Adding, editing and removing samples on an existing complaint.
 *
 * Samples are registered during the wizard as well, but parts often arrive later,
 * so requirement 3.1.6 allows recording them afterwards. Both paths share
 * {@link SampleSupport} and {@link FailureTypeChainValidator}.
 */
@Service
public class SampleService {

    private final SampleMapper sampleMapper;
    private final ComplaintMapper complaintMapper;
    private final ShipmentSampleMapper shipmentSampleMapper;
    private final DocumentNumberService documentNumberService;
    private final AuditLogService auditLogService;
    private final FailureTypeChainValidator failureTypeChainValidator;

    public SampleService(SampleMapper sampleMapper,
                         ComplaintMapper complaintMapper,
                         ShipmentSampleMapper shipmentSampleMapper,
                         DocumentNumberService documentNumberService,
                         AuditLogService auditLogService,
                         FailureTypeChainValidator failureTypeChainValidator) {
        this.sampleMapper = sampleMapper;
        this.complaintMapper = complaintMapper;
        this.shipmentSampleMapper = shipmentSampleMapper;
        this.documentNumberService = documentNumberService;
        this.auditLogService = auditLogService;
        this.failureTypeChainValidator = failureTypeChainValidator;
    }

    @Transactional
    public String add(String complaintId, ComplaintRequests.Sample form) {
        requireComplaint(complaintId);
        validateChain(form);

        String sampleId = documentNumberService.nextSampleId();
        sampleMapper.insert(SampleSupport.newEntity(form, complaintId, sampleId));

        auditLogService.record(AuditActions.CREATE, "Sample", complaintId,
                "登记客诉样品：" + sampleId);
        return sampleId;
    }

    @Transactional
    public void update(String complaintId, String sampleId, ComplaintRequests.Sample form) {
        requireComplaint(complaintId);
        Sample entity = requireSampleOfComplaint(sampleId, complaintId);
        validateChain(form);

        SampleSupport.applyFields(entity, form);
        sampleMapper.updateById(entity);

        auditLogService.record(AuditActions.UPDATE, "Sample", complaintId,
                "修改客诉样品：" + sampleId);
    }

    /**
     * Sample rows cascade away from their shipment links, so deleting one that a
     * batch still carries would silently empty that batch. Refusing instead makes
     * the consequence explicit.
     */
    @Transactional
    public void remove(String complaintId, String sampleId) {
        requireComplaint(complaintId);
        requireSampleOfComplaint(sampleId, complaintId);

        int links = shipmentSampleMapper.countLiveLinksForSample(sampleId);
        if (links > 0) {
            throw new IllegalStateException(
                    "该样品已被 " + links + " 个物流批次引用，请先从批次中移除后再删除");
        }

        sampleMapper.deleteById(sampleId);
        auditLogService.record(AuditActions.DELETE, "Sample", complaintId,
                "删除客诉样品：" + sampleId);
    }

    private void validateChain(ComplaintRequests.Sample form) {
        List<String> errors = new ArrayList<>();
        failureTypeChainValidator.validate(List.of(form), errors);
        if (!errors.isEmpty()) {
            throw new IllegalArgumentException(String.join("；", errors));
        }
    }

    private void requireComplaint(String complaintId) {
        if (complaintMapper.selectById(complaintId) == null) {
            throw new NotFoundException("投诉单不存在：" + complaintId);
        }
    }

    private Sample requireSampleOfComplaint(String sampleId, String complaintId) {
        Sample entity = sampleMapper.selectById(sampleId);
        if (entity == null || !complaintId.equals(entity.getComplaintId())) {
            throw new NotFoundException("样品不属于该投诉单：" + sampleId);
        }
        return entity;
    }
}
