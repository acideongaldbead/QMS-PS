package com.nexperia.qms.auth;

import com.nexperia.qms.auth.dto.ChangePasswordRequest;
import com.nexperia.qms.auth.dto.LoginRequest;
import com.nexperia.qms.auth.dto.LoginResult;
import com.nexperia.qms.auth.dto.MeResponse;
import jakarta.validation.Valid;
import org.springframework.http.HttpStatus;
import org.springframework.security.core.Authentication;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.ResponseStatus;
import org.springframework.web.bind.annotation.RestController;

@RestController
@RequestMapping("/api/auth")
public class AuthController {

    private final AuthService authService;

    public AuthController(AuthService authService) {
        this.authService = authService;
    }

    @PostMapping("/login")
    public LoginResult login(@Valid @RequestBody LoginRequest request) {
        return authService.login(request.username(), request.password());
    }

    @GetMapping("/me")
    public MeResponse me(Authentication authentication) {
        return authService.me(authentication);
    }

    /**
     * Changes the caller's own password. Reachable even while a forced change is
     * pending, which is the point: it is the way out of that state.
     */
    @PostMapping("/change-password")
    @ResponseStatus(HttpStatus.NO_CONTENT)
    public void changePassword(Authentication authentication,
                               @Valid @RequestBody ChangePasswordRequest request) {
        authService.changePassword(authentication, request);
    }
}
