package com.pipelinepilot.demo.api;

import com.pipelinepilot.demo.model.User;
import com.pipelinepilot.demo.service.UserService;
import io.micrometer.core.annotation.Timed;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RestController;

import java.util.List;

@RestController
public class UserController {

    private final UserService userService;

    public UserController(UserService userService) {
        this.userService = userService;
    }

    @Timed(value = "pipeline_pilot_users_seconds", description = "Time spent on /users")
    @GetMapping("/users")
    public List<User> users() {
        return userService.getUsers();
    }
}
