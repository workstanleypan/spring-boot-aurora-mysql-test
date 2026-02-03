#!/bin/bash

# Test script for built-in LoggerNameLevelRewritePolicy
# 测试内置 RewritePolicy 的脚本

echo "╔════════════════════════════════════════════════════════════════╗"
echo "║  Testing Built-in LoggerNameLevelRewritePolicy                ║"
echo "╚════════════════════════════════════════════════════════════════╝"
echo ""

# Check if JAR exists
JAR_FILE="target/spring-boot-mysql-test-1.0.0.jar"
if [ ! -f "$JAR_FILE" ]; then
    echo "❌ JAR file not found: $JAR_FILE"
    echo "   Please run: mvn clean package -DskipTests"
    exit 1
fi

echo "✅ JAR file found: $JAR_FILE"
echo ""

# Check log4j2-spring.xml in JAR
echo "📋 Checking log4j2-spring.xml in JAR..."
jar xf "$JAR_FILE" BOOT-INF/classes/log4j2-spring.xml 2>/dev/null
if [ -f "BOOT-INF/classes/log4j2-spring.xml" ]; then
    echo "✅ log4j2-spring.xml found in JAR"
    
    # Check for LoggerNameLevelRewritePolicy
    if grep -q "LoggerNameLevelRewritePolicy" BOOT-INF/classes/log4j2-spring.xml; then
        echo "✅ LoggerNameLevelRewritePolicy configuration found"
    else
        echo "❌ LoggerNameLevelRewritePolicy configuration NOT found"
    fi
    
    # Check that packages attribute is removed
    if grep -q 'packages="com.test.logging"' BOOT-INF/classes/log4j2-spring.xml; then
        echo "⚠️  WARNING: packages attribute still present (should be removed)"
    else
        echo "✅ packages attribute removed (correct)"
    fi
    
    # Cleanup
    rm -rf BOOT-INF
else
    echo "❌ log4j2-spring.xml NOT found in JAR"
fi
echo ""

# Check for custom LevelRewritePolicy class (should NOT exist)
echo "🔍 Checking for custom LevelRewritePolicy class..."
if jar tf "$JAR_FILE" | grep -q "LevelRewritePolicy.class"; then
    echo "⚠️  WARNING: Custom LevelRewritePolicy.class found in JAR (should be removed)"
else
    echo "✅ Custom LevelRewritePolicy.class NOT in JAR (correct)"
fi
echo ""

# Check Log4j2 version
echo "📦 Checking Log4j2 version in JAR..."
LOG4J_VERSION=$(jar tf "$JAR_FILE" | grep "log4j-core-.*\.jar" | head -1 | sed 's/.*log4j-core-\(.*\)\.jar.*/\1/')
if [ -n "$LOG4J_VERSION" ]; then
    echo "✅ Log4j2 Core version: $LOG4J_VERSION"
    
    # Check if version >= 2.4 (required for LoggerNameLevelRewritePolicy)
    MAJOR=$(echo "$LOG4J_VERSION" | cut -d. -f1)
    MINOR=$(echo "$LOG4J_VERSION" | cut -d. -f2)
    
    if [ "$MAJOR" -gt 2 ] || ([ "$MAJOR" -eq 2 ] && [ "$MINOR" -ge 4 ]); then
        echo "✅ Version check passed (>= 2.4 required)"
    else
        echo "❌ Version check failed (< 2.4, LoggerNameLevelRewritePolicy not available)"
    fi
else
    echo "⚠️  Could not determine Log4j2 version"
fi
echo ""

echo "╔════════════════════════════════════════════════════════════════╗"
echo "║  Verification Complete                                         ║"
echo "╚════════════════════════════════════════════════════════════════╝"
echo ""
echo "📝 Summary:"
echo "   - Using Log4j2 built-in LoggerNameLevelRewritePolicy"
echo "   - No custom Java code required"
echo "   - Configuration in log4j2-spring.xml only"
echo ""
echo "🚀 To run the application:"
echo "   ./run-aurora.sh              # Aurora cluster"
echo "   ./run-aurora-bg-debug.sh     # Aurora with BG debug"
echo "   ./run-rds.sh                 # RDS instance"
echo ""
