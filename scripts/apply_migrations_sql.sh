#!/bin/bash
# Generate a single SQL file with all migrations for manual application
# Usage: ./scripts/apply_migrations_sql.sh
#
# This creates a combined SQL file that you can paste into the
# Supabase Dashboard SQL Editor to apply all migrations at once.

set -e

OUTPUT_FILE="all_migrations.sql"
MIGRATIONS_DIR="supabase/migrations"

echo "=== Generating Combined Migration File ==="
echo ""

# Clear output file
> "$OUTPUT_FILE"

# Add header
cat >> "$OUTPUT_FILE" << 'EOF'
-- =====================================================
-- 5BIRR Combined Migrations
-- Apply this in the Supabase Dashboard SQL Editor:
-- https://supabase.com/dashboard/project/xnwieehlrhrffoikpglj/sql/new
-- =====================================================

-- Disable transaction for DDL (each statement auto-commits)
SET client_min_messages = WARNING;

EOF

# Concatenate all migrations in order
for file in $(ls "$MIGRATIONS_DIR"/*.sql | sort); do
    filename=$(basename "$file")
    echo "  Adding $filename..."
    
    echo "" >> "$OUTPUT_FILE"
    echo "-- =====================================================" >> "$OUTPUT_FILE"
    echo "-- Migration: $filename" >> "$OUTPUT_FILE"
    echo "-- =====================================================" >> "$OUTPUT_FILE"
    echo "" >> "$OUTPUT_FILE"
    cat "$file" >> "$OUTPUT_FILE"
    echo "" >> "$OUTPUT_FILE"
done

echo ""
echo "✅ Generated $OUTPUT_FILE ($(wc -l < "$OUTPUT_FILE") lines)"
echo ""
echo "Next steps:"
echo "  1. Open https://supabase.com/dashboard/project/xnwieehlrhrffoikpglj/sql/new"
echo "  2. Copy the contents of $OUTPUT_FILE"
echo "  3. Paste into the SQL Editor"
echo "  4. Click 'Run' to execute all migrations"
echo ""
echo "Note: If any migration fails, the Dashboard will show the error."
echo "      You can then apply remaining migrations individually."
