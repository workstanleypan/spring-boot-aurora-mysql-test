package com.test.controller;

import com.test.model.User;
import com.test.service.UserService;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

import javax.sql.DataSource;
import java.sql.Connection;
import java.sql.DatabaseMetaData;
import java.util.HashMap;
import java.util.List;
import java.util.Map;

/**
 * User REST Controller
 * 提供 RESTful API
 */
@RestController
@RequestMapping("/api")
public class UserController {
    
    private static final Logger log = LoggerFactory.getLogger(UserController.class);
    
    private final UserService userService;
    private final DataSource dataSource;
    
    public UserController(UserService userService, DataSource dataSource) {
        this.userService = userService;
        this.dataSource = dataSource;
    }
    
    /**
     * 测试端点 - 验证数据库连接
     */
    @GetMapping("/test")
    public ResponseEntity<Map<String, Object>> test() {
        log.info("Test endpoint called");
        Map<String, Object> response = new HashMap<>();
        
        try (Connection conn = dataSource.getConnection()) {
            DatabaseMetaData metaData = conn.getMetaData();
            
            response.put("status", "success");
            response.put("message", "Database connection successful");
            response.put("database", metaData.getDatabaseProductName());
            response.put("version", metaData.getDatabaseProductVersion());
            response.put("driver", metaData.getDriverName());
            response.put("driverVersion", metaData.getDriverVersion());
            response.put("url", metaData.getURL());
            response.put("userCount", userService.getUserCount());
            
            log.info("✅ Database connection test successful");
            return ResponseEntity.ok(response);
            
        } catch (Exception e) {
            log.error("❌ Database connection test failed", e);
            response.put("status", "error");
            response.put("message", "Database connection failed: " + e.getMessage());
            return ResponseEntity.status(500).body(response);
        }
    }
    
    /**
     * 获取所有用户
     */
    @GetMapping("/users")
    public ResponseEntity<List<User>> getAllUsers() {
        log.info("GET /api/users");
        List<User> users = userService.getAllUsers();
        return ResponseEntity.ok(users);
    }
    
    /**
     * 根据 ID 获取用户
     */
    @GetMapping("/users/{id}")
    public ResponseEntity<User> getUserById(@PathVariable Long id) {
        log.info("GET /api/users/{}", id);
        User user = userService.getUserById(id);
        if (user != null) {
            return ResponseEntity.ok(user);
        }
        return ResponseEntity.notFound().build();
    }
    
    /**
     * 创建用户
     */
    @PostMapping("/users")
    public ResponseEntity<Map<String, Object>> createUser(@RequestBody Map<String, String> request) {
        String name = request.get("name");
        log.info("POST /api/users with name={}", name);
        
        if (name == null || name.trim().isEmpty()) {
            return ResponseEntity.badRequest().body(Map.of("error", "Name is required"));
        }
        
        User user = userService.createUser(name);
        if (user != null) {
            return ResponseEntity.ok(Map.of("message", "User created", "name", name));
        }
        return ResponseEntity.status(500).body(Map.of("error", "Failed to create user"));
    }
    
    /**
     * 更新用户
     */
    @PutMapping("/users/{id}")
    public ResponseEntity<Map<String, Object>> updateUser(
            @PathVariable Long id,
            @RequestBody Map<String, String> request) {
        String name = request.get("name");
        log.info("PUT /api/users/{} with name={}", id, name);
        
        if (name == null || name.trim().isEmpty()) {
            return ResponseEntity.badRequest().body(Map.of("error", "Name is required"));
        }
        
        boolean updated = userService.updateUser(id, name);
        if (updated) {
            return ResponseEntity.ok(Map.of("message", "User updated", "id", id, "name", name));
        }
        return ResponseEntity.notFound().build();
    }
    
    /**
     * 删除用户
     */
    @DeleteMapping("/users/{id}")
    public ResponseEntity<Map<String, Object>> deleteUser(@PathVariable Long id) {
        log.info("DELETE /api/users/{}", id);
        boolean deleted = userService.deleteUser(id);
        if (deleted) {
            return ResponseEntity.ok(Map.of("message", "User deleted", "id", id));
        }
        return ResponseEntity.notFound().build();
    }
    
    /**
     * 获取用户统计
     */
    @GetMapping("/users/stats")
    public ResponseEntity<Map<String, Object>> getUserStats() {
        log.info("GET /api/users/stats");
        long count = userService.getUserCount();
        return ResponseEntity.ok(Map.of("totalUsers", count));
    }
}
