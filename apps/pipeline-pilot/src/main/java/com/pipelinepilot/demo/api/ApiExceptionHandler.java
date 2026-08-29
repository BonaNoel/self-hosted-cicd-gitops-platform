package com.pipelinepilot.demo.api;

import jakarta.validation.ConstraintViolationException;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.MethodArgumentNotValidException;
import org.springframework.web.bind.annotation.ExceptionHandler;
import org.springframework.web.bind.annotation.RestControllerAdvice;

import java.util.Map;

@RestControllerAdvice
public class ApiExceptionHandler {

    @ExceptionHandler({MethodArgumentNotValidException.class, ConstraintViolationException.class})
    public ResponseEntity<Map<String, String>> handleValidation(Exception exception) {
        return ResponseEntity.badRequest().body(Map.of("error", "Invalid request", "details", exception.getMessage()));
    }

    @ExceptionHandler(InterruptedException.class)
    public ResponseEntity<Map<String, String>> handleInterrupted(InterruptedException exception) {
        Thread.currentThread().interrupt();
        return ResponseEntity.status(HttpStatus.INTERNAL_SERVER_ERROR)
                .body(Map.of("error", "Load simulation interrupted", "details", exception.getMessage()));
    }
}
