#!/bin/bash

# Cleanup backup and unnecessary files
# 清理备份文件和不必要的文件

echo "╔════════════════════════════════════════════════════════════════╗"
echo "║  Cleaning up backup and unnecessary files                      ║"
echo "╚════════════════════════════════════════════════════════════════╝"
echo ""

# List files to be removed
echo "📋 Files to be removed:"
echo ""

FILES_TO_REMOVE=(
    "src/main/resources/log4j2-spring.xml.bak"
    "src/main/resources/log4j2-spring.xml.backup-20260114-090147"
    "src/main/resources/log4j2-spring copy.xml"
    "src/main/java/com/test/logging/LevelRewritePolicy.java.bak"
    "src/main/resources/log4j2-spring-with-rewrite-policy.xml"
)

for file in "${FILES_TO_REMOVE[@]}"; do
    if [ -f "$file" ]; then
        echo "  ✓ $file"
    fi
done

echo ""
read -p "❓ Do you want to remove these files? (y/N): " -n 1 -r
echo ""

if [[ $REPLY =~ ^[Yy]$ ]]; then
    echo ""
    echo "🗑️  Removing files..."
    
    for file in "${FILES_TO_REMOVE[@]}"; do
        if [ -f "$file" ]; then
            rm "$file"
            echo "  ✅ Removed: $file"
        fi
    done
    
    echo ""
    echo "✅ Cleanup completed!"
else
    echo ""
    echo "❌ Cleanup cancelled"
fi

echo ""
