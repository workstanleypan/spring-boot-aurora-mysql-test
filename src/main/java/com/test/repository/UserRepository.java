package com.test.repository;

import com.test.model.User;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.jdbc.core.RowMapper;
import org.springframework.stereotype.Repository;

import java.sql.ResultSet;
import java.sql.SQLException;
import java.util.List;

/**
 * User Repository
 * Uses JdbcTemplate for database operations
 */
@Repository
public class UserRepository {
    
    private static final Logger log = LoggerFactory.getLogger(UserRepository.class);
    
    private final JdbcTemplate jdbcTemplate;
    
    public UserRepository(JdbcTemplate jdbcTemplate) {
        this.jdbcTemplate = jdbcTemplate;
    }
    
    /**
     * Find all users
     */
    public List<User> findAll() {
        String sql = "SELECT id, name, created_at FROM test_table";
        log.debug("Executing query: {}", sql);
        return jdbcTemplate.query(sql, new UserRowMapper());
    }
    
    /**
     * Find user by ID
     */
    public User findById(Long id) {
        String sql = "SELECT id, name, created_at FROM test_table WHERE id = ?";
        log.debug("Executing query: {} with id={}", sql, id);
        List<User> users = jdbcTemplate.query(sql, new UserRowMapper(), id);
        return users.isEmpty() ? null : users.get(0);
    }
    
    /**
     * Insert user
     */
    public int insert(String name) {
        String sql = "INSERT INTO test_table (name) VALUES (?)";
        log.debug("Executing insert: {} with name={}", sql, name);
        return jdbcTemplate.update(sql, name);
    }
    
    /**
     * Update user
     */
    public int update(Long id, String name) {
        String sql = "UPDATE test_table SET name = ? WHERE id = ?";
        log.debug("Executing update: {} with name={}, id={}", sql, name, id);
        return jdbcTemplate.update(sql, name, id);
    }
    
    /**
     * Delete user
     */
    public int delete(Long id) {
        String sql = "DELETE FROM test_table WHERE id = ?";
        log.debug("Executing delete: {} with id={}", sql, id);
        return jdbcTemplate.update(sql, id);
    }
    
    /**
     * Count users
     */
    public long count() {
        String sql = "SELECT COUNT(*) FROM test_table";
        log.debug("Executing count: {}", sql);
        Long count = jdbcTemplate.queryForObject(sql, Long.class);
        return count != null ? count : 0;
    }
    
    /**
     * RowMapper for User
     */
    private static class UserRowMapper implements RowMapper<User> {
        @Override
        public User mapRow(ResultSet rs, int rowNum) throws SQLException {
            User user = new User();
            user.setId(rs.getLong("id"));
            user.setName(rs.getString("name"));
            user.setCreatedAt(rs.getTimestamp("created_at").toLocalDateTime());
            return user;
        }
    }
}
