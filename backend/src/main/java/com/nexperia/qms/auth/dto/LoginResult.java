package com.nexperia.qms.auth.dto;

public record LoginResult(String accessToken, MeResponse user) {
}
