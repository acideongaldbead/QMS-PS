package com.nexperia.qms.common.exception;

import com.nexperia.qms.common.audit.AuditActions;
import com.nexperia.qms.common.audit.AuditLogService;
import com.nexperia.qms.common.security.CurrentUserContext;
import jakarta.servlet.http.HttpServletRequest;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.dao.DataIntegrityViolationException;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.http.converter.HttpMessageNotReadableException;
import org.springframework.web.bind.MissingServletRequestParameterException;
import org.springframework.web.method.annotation.MethodArgumentTypeMismatchException;
import org.springframework.security.access.AccessDeniedException;
import org.springframework.security.authentication.BadCredentialsException;
import org.springframework.security.authentication.DisabledException;
import org.springframework.security.authentication.LockedException;
import org.springframework.validation.FieldError;
import org.springframework.web.bind.MethodArgumentNotValidException;
import org.springframework.web.bind.annotation.ExceptionHandler;
import org.springframework.web.bind.annotation.RestControllerAdvice;
import org.springframework.web.context.request.RequestContextHolder;
import org.springframework.web.context.request.ServletRequestAttributes;
import org.springframework.web.multipart.MaxUploadSizeExceededException;

import java.util.LinkedHashMap;
import java.util.Map;
import java.util.stream.Collectors;

/**
 * Turns exceptions into a consistent {status, message} body, which the frontend
 * reads via errorMessage() in api/http.ts.
 */
@RestControllerAdvice
public class GlobalExceptionHandler {

    private static final Logger log = LoggerFactory.getLogger(GlobalExceptionHandler.class);

    private final AuditLogService auditLogService;

    public GlobalExceptionHandler(AuditLogService auditLogService) {
        this.auditLogService = auditLogService;
    }

    @ExceptionHandler({BadCredentialsException.class, LockedException.class, DisabledException.class})
    public ResponseEntity<Map<String, Object>> handleAuthFailure(RuntimeException ex) {
        return body(HttpStatus.UNAUTHORIZED, ex.getMessage());
    }

    @ExceptionHandler(AccessDeniedException.class)
    public ResponseEntity<Map<String, Object>> handleDenied(AccessDeniedException ex) {
        // A denial raised by Spring Security's own authorization carries a generic
        // English message; one raised by a business rule explains itself. Prefer the
        // explanation, fall back to a neutral sentence for the former.
        String message = ex.getMessage();
        if (message == null || message.isBlank() || "Access Denied".equals(message)) {
            message = "无权限执行该操作";
        }
        auditDenied(message);
        return body(HttpStatus.FORBIDDEN, message);
    }

    /**
     * Requirement 3.12 (PS-113 AC3): a refused action must leave an audit trail.
     * Recorded in its own transaction -- the refusal has already failed the
     * request, and nothing else is going to commit.
     */
    private void auditDenied(String message) {
        String operator = CurrentUserContext.employeeId();
        if (operator == null) {
            // An anonymous request has nobody to attribute the refusal to; that is
            // an authentication problem, answered with 401 elsewhere.
            return;
        }
        HttpServletRequest request = currentRequest();
        String target = request == null
                ? "(unknown)"
                : request.getMethod() + " " + request.getRequestURI();
        auditLogService.recordRegardlessOfOutcome(AuditActions.ACCESS_DENIED, "AccessDenied", null,
                "越权访问被拦截：" + target + "；" + message);
    }

    private static HttpServletRequest currentRequest() {
        var attributes = RequestContextHolder.getRequestAttributes();
        return attributes instanceof ServletRequestAttributes servletAttributes
                ? servletAttributes.getRequest()
                : null;
    }

    @ExceptionHandler(MethodArgumentNotValidException.class)
    public ResponseEntity<Map<String, Object>> handleValidation(MethodArgumentNotValidException ex) {
        String detail = ex.getBindingResult().getFieldErrors().stream()
                .map(f -> f.getField() + ": " + defaultMessage(f))
                .collect(Collectors.joining("; "));
        return body(HttpStatus.BAD_REQUEST, detail.isEmpty() ? "请求参数不合法" : detail);
    }

    /**
     * A body that cannot be parsed is the caller's mistake, not a server fault:
     * answering 500 would hide a broken client behind an internal error.
     */
    @ExceptionHandler(HttpMessageNotReadableException.class)
    public ResponseEntity<Map<String, Object>> handleUnreadableBody(HttpMessageNotReadableException ex) {
        log.warn("Rejected an unreadable request body: {}", ex.getMostSpecificCause().getMessage());
        return body(HttpStatus.BAD_REQUEST, "请求内容格式不正确");
    }

    /**
     * Raised by the servlet container before the controller runs, when a multipart
     * request exceeds spring.servlet.multipart.max-file-size.
     */
    @ExceptionHandler(MaxUploadSizeExceededException.class)
    public ResponseEntity<Map<String, Object>> handleTooLarge(MaxUploadSizeExceededException ex) {
        return body(HttpStatus.BAD_REQUEST, "上传文件超过大小上限");
    }

    @ExceptionHandler(MissingServletRequestParameterException.class)
    public ResponseEntity<Map<String, Object>> handleMissingParameter(MissingServletRequestParameterException ex) {
        return body(HttpStatus.BAD_REQUEST, "缺少必要的参数：" + ex.getParameterName());
    }

    @ExceptionHandler(MethodArgumentTypeMismatchException.class)
    public ResponseEntity<Map<String, Object>> handleTypeMismatch(MethodArgumentTypeMismatchException ex) {
        return body(HttpStatus.BAD_REQUEST, "参数格式不正确：" + ex.getName());
    }

    @ExceptionHandler(IllegalArgumentException.class)
    public ResponseEntity<Map<String, Object>> handleIllegalArgument(IllegalArgumentException ex) {
        return body(HttpStatus.BAD_REQUEST, ex.getMessage());
    }

    @ExceptionHandler(IllegalStateException.class)
    public ResponseEntity<Map<String, Object>> handleIllegalState(IllegalStateException ex) {
        return body(HttpStatus.CONFLICT, ex.getMessage());
    }

    @ExceptionHandler(NotFoundException.class)
    public ResponseEntity<Map<String, Object>> handleNotFound(NotFoundException ex) {
        return body(HttpStatus.NOT_FOUND, ex.getMessage());
    }

    @ExceptionHandler(DataIntegrityViolationException.class)
    public ResponseEntity<Map<String, Object>> handleIntegrity(DataIntegrityViolationException ex) {
        var translation = DataIntegrityTranslator.translate(ex);
        if (translation.constraintName() == null) {
            log.warn("Data integrity violation without a mapped constraint", ex);
        } else {
            log.warn("Data integrity violation: constraint={}", translation.constraintName());
        }
        return body(HttpStatus.BAD_REQUEST, translation.message());
    }

    @ExceptionHandler(Exception.class)
    public ResponseEntity<Map<String, Object>> handleOther(Exception ex) {
        log.error("Unhandled exception", ex);
        return body(HttpStatus.INTERNAL_SERVER_ERROR, "服务器内部错误");
    }

    private static String defaultMessage(FieldError fieldError) {
        return fieldError.getDefaultMessage() == null ? "invalid" : fieldError.getDefaultMessage();
    }

    private static ResponseEntity<Map<String, Object>> body(HttpStatus status, String message) {
        Map<String, Object> payload = new LinkedHashMap<>();
        payload.put("status", status.value());
        payload.put("message", message == null ? status.getReasonPhrase() : message);
        return ResponseEntity.status(status).body(payload);
    }
}
