#!/bin/bash
# ============================================================
# Build script with configurable Spring Boot / JDK / Wrapper versions
# ============================================================
# Usage:
#   ./build.sh                                    # Default: SB 3.4.2, JDK 17, Wrapper 3.2.0
#   ./build.sh --sb 3.2.0                         # Spring Boot 3.2.0
#   ./build.sh --sb 2.7.18 --jdk 11               # Spring Boot 2.x + JDK 11
#   ./build.sh --sb 3.4.2 --jdk 17 --wrapper 3.2.0  # Full custom
#   ./build.sh --list                             # Show common version combos
# ============================================================

set -e

# Defaults
SB_VERSION="3.4.2"
JDK_VERSION="17"
WRAPPER_VERSION="3.2.0"

show_help() {
    echo "╔════════════════════════════════════════════════════════════════╗"
    echo "║   Build with Custom Spring Boot / JDK / Wrapper Versions      ║"
    echo "╚════════════════════════════════════════════════════════════════╝"
    echo ""
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  --sb VERSION        Spring Boot version (default: $SB_VERSION)"
    echo "  --jdk VERSION       JDK version: 8, 11, 17, 21 (default: $JDK_VERSION)"
    echo "  --wrapper VERSION   AWS JDBC Wrapper version (default: $WRAPPER_VERSION)"
    echo "  --list              Show common version combinations"
    echo "  --help              Show this help"
    echo ""
    echo "Examples:"
    echo "  $0                                          # Default versions"
    echo "  $0 --sb 3.2.0                               # Spring Boot 3.2.0"
    echo "  $0 --sb 2.7.18 --jdk 11                     # Spring Boot 2.x + JDK 11"
    echo "  $0 --sb 3.4.2 --jdk 21 --wrapper 3.2.0      # Full custom"
}

show_combos() {
    echo "╔════════════════════════════════════════════════════════════════╗"
    echo "║   Common Version Combinations                                 ║"
    echo "╚════════════════════════════════════════════════════════════════╝"
    echo ""
    echo "  Spring Boot 2.7.x (requires JDK 8/11/17):"
    echo "    $0 --sb 2.7.18 --jdk 11"
    echo "    $0 --sb 2.7.18 --jdk 17"
    echo ""
    echo "  Spring Boot 3.0.x - 3.2.x (requires JDK 17+):"
    echo "    $0 --sb 3.0.13 --jdk 17"
    echo "    $0 --sb 3.1.12 --jdk 17"
    echo "    $0 --sb 3.2.0 --jdk 17"
    echo ""
    echo "  Spring Boot 3.3.x - 3.4.x (requires JDK 17+, supports 21):"
    echo "    $0 --sb 3.3.7 --jdk 17"
    echo "    $0 --sb 3.4.2 --jdk 17"
    echo "    $0 --sb 3.4.2 --jdk 21"
    echo ""
    echo "  AWS JDBC Wrapper versions:"
    echo "    2.5.3, 2.5.4, 3.0.0, 3.1.0, 3.2.0"
    echo ""
    echo "  JDK available on this machine:"
    ls /usr/lib/jvm/ 2>/dev/null | grep -E "^java-[0-9]+" | sort -u || echo "    (could not detect)"
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --sb)       SB_VERSION="$2"; shift 2 ;;
        --jdk)      JDK_VERSION="$2"; shift 2 ;;
        --wrapper)  WRAPPER_VERSION="$2"; shift 2 ;;
        --list)     show_combos; exit 0 ;;
        --help|-h)  show_help; exit 0 ;;
        *)          echo "Unknown option: $1"; show_help; exit 1 ;;
    esac
done

echo "╔════════════════════════════════════════════════════════════════╗"
echo "║   Building with Custom Versions                               ║"
echo "╚════════════════════════════════════════════════════════════════╝"
echo ""
echo "📋 Build Configuration:"
echo "   Spring Boot     : $SB_VERSION"
echo "   JDK             : $JDK_VERSION"
echo "   JDBC Wrapper    : $WRAPPER_VERSION"
echo ""

# ============================================================
# Version compatibility check
# ============================================================
SB_MAJOR=$(echo "$SB_VERSION" | cut -d. -f1)

if [ "$SB_MAJOR" -ge 3 ] && [ "$JDK_VERSION" -lt 17 ]; then
    echo "❌ Error: Spring Boot 3.x requires JDK 17+"
    echo "   You specified: Spring Boot $SB_VERSION + JDK $JDK_VERSION"
    echo "   Try: $0 --sb $SB_VERSION --jdk 17"
    exit 1
fi

if [ "$SB_MAJOR" -lt 2 ]; then
    echo "❌ Error: Spring Boot version must be 2.x or 3.x"
    exit 1
fi

# ============================================================
# Locate JAVA_HOME for the requested JDK version
# ============================================================
JAVA_HOME_CANDIDATE=""

# Try Amazon Corretto first, then OpenJDK
for prefix in "java-${JDK_VERSION}-amazon-corretto" "java-${JDK_VERSION}-openjdk" "java-${JDK_VERSION}"; do
    candidate=$(ls -d /usr/lib/jvm/${prefix}* 2>/dev/null | head -1)
    if [ -n "$candidate" ] && [ -d "$candidate" ]; then
        JAVA_HOME_CANDIDATE="$candidate"
        break
    fi
done

if [ -z "$JAVA_HOME_CANDIDATE" ]; then
    echo "❌ Error: JDK $JDK_VERSION not found on this machine"
    echo ""
    echo "Available JDKs:"
    ls /usr/lib/jvm/ 2>/dev/null | grep -E "^java-[0-9]+" | sort -u
    echo ""
    echo "Install with: sudo yum install java-${JDK_VERSION}-amazon-corretto-devel"
    exit 1
fi

export JAVA_HOME="$JAVA_HOME_CANDIDATE"
echo "☕ JAVA_HOME: $JAVA_HOME"
echo "   $($JAVA_HOME/bin/java -version 2>&1 | head -1)"
echo ""

# ============================================================
# Build
# ============================================================
echo "🔨 Building..."
echo ""

mvn clean package -DskipTests \
    -Dspring-boot.version="$SB_VERSION" \
    -Djava.version="$JDK_VERSION" \
    -Daws-jdbc-wrapper.version="$WRAPPER_VERSION"

echo ""

# Find the built JAR
JAR_NAME="spring-boot-aurora-mysql-test-sb${SB_VERSION}-jdk${JDK_VERSION}-wrapper${WRAPPER_VERSION}.jar"
JAR_PATH="target/$JAR_NAME"

if [ -f "$JAR_PATH" ]; then
    echo "╔════════════════════════════════════════════════════════════════╗"
    echo "║   Build Successful                                            ║"
    echo "╚════════════════════════════════════════════════════════════════╝"
    echo ""
    echo "📦 JAR: $JAR_PATH"
    echo "   Size: $(du -h "$JAR_PATH" | cut -f1)"
    echo ""
    echo "🚀 Run with:"
    echo "   # Single instance:"
    echo "   JAR_FILE=$JAR_PATH ./run-aurora.sh"
    echo ""
    echo "   # Multi-instance (same cluster):"
    echo "   JAR_FILE=$JAR_PATH ./run-instance1.sh"
    echo "   JAR_FILE=$JAR_PATH ./run-instance2.sh"
    echo ""
    echo "   # Or set JAVA_HOME for runtime JDK:"
    echo "   export JAVA_HOME=$JAVA_HOME"
    echo "   JAR_FILE=$JAR_PATH ./run-aurora.sh"
else
    echo "⚠️  Expected JAR not found at $JAR_PATH"
    echo "   Available JARs:"
    ls -la target/*.jar 2>/dev/null
fi
