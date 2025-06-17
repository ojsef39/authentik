#!/bin/bash

set -e

echo "🚀 Starting Docusaurus build process..."
echo "📊 Initial system info:"
echo "Node version: $(node --version)"
echo "NPM version: $(npm --version)"

# Create a temporary file for build output
BUILD_OUTPUT=$(mktemp)
trap "rm -f $BUILD_OUTPUT" EXIT

# Function to print memory usage
print_memory_usage() {
    if command -v free >/dev/null 2>&1; then
        echo "💾 Memory usage:"
        free -h
    elif command -v vm_stat >/dev/null 2>&1; then
        echo "💾 Memory usage (macOS):"
        vm_stat | head -5
    else
        echo "💾 Memory monitoring not available on this system"
    fi
    echo ""
}

# Function to monitor memory in background
monitor_memory() {
    while true; do
        sleep 30
        if command -v free >/dev/null 2>&1; then
            echo "⏰ $(date '+%H:%M:%S') - Memory: $(free -h | grep '^Mem:' | awk '{print "Used: " $3 "/" $2 " (" $3/$2*100 "%)"}' 2>/dev/null || echo 'monitoring failed')"
        fi
    done &
    MONITOR_PID=$!
}

print_memory_usage

echo "🏗️  Starting Docusaurus build..."

# Set Node.js memory options
export NODE_OPTIONS="--max_old_space_size=11264 --max-semi-space-size=1024"

# Start memory monitoring
monitor_memory

# Run the build and capture all output
echo "📝 Build output will be shown in real-time:"
echo "----------------------------------------"

# Use timeout to prevent infinite hanging (adjust time as needed)
timeout 30m npm run build:all 2>&1 | tee "$BUILD_OUTPUT"
BUILD_EXIT_CODE=${PIPESTATUS[0]}

# Stop memory monitoring
kill $MONITOR_PID 2>/dev/null || true

echo "----------------------------------------"
echo "📊 Build process completed with exit code: $BUILD_EXIT_CODE"

print_memory_usage

if [ $BUILD_EXIT_CODE -eq 0 ]; then
    echo "✅ Build completed successfully!"

    if [ -d "build" ]; then
        echo "📁 Build output size:"
        du -sh build/
        echo "📄 Build contents:"
        ls -la build/
    fi
else
    echo "❌ Build failed with exit code: $BUILD_EXIT_CODE"
    echo ""

    case $BUILD_EXIT_CODE in
        1)
            echo "💡 Exit code 1 analysis:"
            echo "   - JavaScript/TypeScript compilation error"
            echo "   - Out of memory error"
            echo "   - Plugin or configuration error"
            ;;
        124)
            echo "💡 Exit code 124: Build timed out (exceeded 30 minutes)"
            echo "   Consider increasing timeout or optimizing build"
            ;;
        130)
            echo "💡 Exit code 130: Process was interrupted (Ctrl+C)"
            ;;
        137)
            echo "💡 Exit code 137: Process was killed by OOM killer"
            echo "   System ran out of memory - consider:"
            echo "   - Reducing --max_old_space_size"
            echo "   - Splitting build into smaller chunks"
            echo "   - Using build optimization plugins"
            ;;
        *)
            echo "💡 Unexpected exit code: $BUILD_EXIT_CODE"
            ;;
    esac

    echo ""
    echo "🔍 Analyzing build output for common issues..."

    # Check for memory-related errors
    if grep -qi "heap out of memory\|maximum call stack\|out of memory" "$BUILD_OUTPUT"; then
        echo "❗ Memory-related errors found in build output"
        echo "Last 10 lines before potential memory error:"
        grep -n -i -B5 "heap out of memory\|maximum call stack\|out of memory" "$BUILD_OUTPUT" | tail -10
    fi

    # Check for other common Docusaurus errors
    if grep -qi "error\|failed\|exception" "$BUILD_OUTPUT"; then
        echo "❗ Error messages found in build output:"
        echo "Last 20 lines containing errors:"
        grep -n -i "error\|failed\|exception" "$BUILD_OUTPUT" | tail -20
    fi

    # Show last 20 lines of output for context
    echo ""
    echo "📋 Last 20 lines of build output:"
    tail -20 "$BUILD_OUTPUT"

    # Check system logs for OOM events (if available)
    if command -v journalctl >/dev/null 2>&1; then
        echo ""
        echo "🔍 Checking system logs for OOM events..."
        journalctl --since "10 minutes ago" | grep -i "killed\|memory\|oom" | tail -5 || echo "No recent OOM events found"
    fi

    # Check dmesg for OOM events (if available)
    if command -v dmesg >/dev/null 2>&1; then
        echo ""
        echo "🔍 Checking dmesg for OOM events..."
        dmesg | grep -i "killed\|oom\|memory" | tail -5 || echo "No OOM events found in dmesg"
    fi

    exit $BUILD_EXIT_CODE
fi

echo "🎉 Build process completed successfully!"
