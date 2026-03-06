#!/bin/bash
# ============================================================
# Auto-detect JAVA_HOME from JAR filename
# Source this file: source detect-java.sh
# Then call: detect_java_from_jar "$JAR_FILE"
# ============================================================

detect_java_from_jar() {
    local jar_file="$1"
    
    # Extract JDK version from JAR name (e.g. ...-jdk11-... -> 11)
    local jdk_version=$(echo "$jar_file" | grep -oP 'jdk\K[0-9]+')
    
    if [ -z "$jdk_version" ]; then
        echo "ℹ️  No JDK version in JAR name, using system default java"
        JAVA_CMD="java"
        return
    fi
    
    # If JAVA_HOME is already set and matches, use it
    if [ -n "$JAVA_HOME" ]; then
        local current_version=$("$JAVA_HOME/bin/java" -version 2>&1 | head -1 | grep -oP '"(\K[0-9]+)')
        if [ "$current_version" = "$jdk_version" ]; then
            echo "☕ Using JAVA_HOME=$JAVA_HOME (JDK $jdk_version)"
            JAVA_CMD="$JAVA_HOME/bin/java"
            return
        fi
    fi
    
    # Auto-detect JAVA_HOME for the required version
    local java_home=""
    for prefix in "java-${jdk_version}-amazon-corretto" "java-${jdk_version}-openjdk" "java-${jdk_version}"; do
        local candidate=$(ls -d /usr/lib/jvm/${prefix}* 2>/dev/null | head -1)
        if [ -n "$candidate" ] && [ -d "$candidate" ]; then
            java_home="$candidate"
            break
        fi
    done
    
    if [ -n "$java_home" ]; then
        export JAVA_HOME="$java_home"
        JAVA_CMD="$JAVA_HOME/bin/java"
        echo "☕ Auto-detected JAVA_HOME=$JAVA_HOME (JDK $jdk_version from JAR name)"
        echo "   $($JAVA_CMD -version 2>&1 | head -1)"
    else
        echo "⚠️  JDK $jdk_version not found, falling back to system java"
        echo "   Install with: sudo yum install java-${jdk_version}-amazon-corretto-devel"
        JAVA_CMD="java"
    fi
}
