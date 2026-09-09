#!/bin/bash
# Apply all Supabase migrations to the live project
# Usage: ./scripts/apply_migrations.sh
#
# Prerequisites:
#   1. Install Supabase CLI: https://supabase.com/docs/guides/cli
#   2. Login: supabase login
#   3. Link project: supabase link --project-ref xnwieehlrhrffoikpglj
#
# This script applies all 19 migrations in order.

set -e

echo "=== Supabase Migration Script ==="
echo ""

# Check if supabase CLI is installed
if ! command -v supabase &> /dev/null; then
    echo "❌ Supabase CLI not found."
    echo "   Install it from: https://supabase.com/docs/guides/cli/getting-started"
    echo "   Or run: brew install supabase/tap/supabase"
    exit 1
fi

# Check if linked to project
if ! supabase projects list &> /dev/null; then
    echo "⚠️  Not logged in. Running: supabase login"
    supabase login
fi

echo "Linking to project xnwieehlrhrffoikpglj..."
supabase link --project-ref xnwieehlrhrffoikpglj || true

echo ""
echo "Applying migrations..."
echo ""

# Apply each migration in order
MIGRATIONS_DIR="supabase/migrations"
FAILED=0
SUCCEEDED=0

for file in $(ls "$MIGRATIONS_DIR"/*.sql | sort); do
    filename=$(basename "$file")
    echo -n "  Applying $filename... "
    
    if supabase db execute --file "$file" 2>/dev/null; then
        echo "✅"
        SUCCEEDED=$((SUCCEEDED + 1))
    else
        # Try with supabase migration up for individual files
        if supabase migration up --include-all 2>/dev/null; then
            echo "✅ (via migration up)"
            SUCCEEDED=$((SUCCEEDED + 1))
        else
            echo "❌ FAILED"
            FAILED=$((FAILED + 1))
        fi
    fi
done

echo ""
echo "=== Summary ==="
echo "  Succeeded: $SUCCEEDED"
echo "  Failed: $FAILED"
echo ""

if [ $FAILED -gt 0 ]; then
    echo "⚠️  Some migrations failed. Check the output above for details."
    echo "   You can also apply them manually via the Supabase Dashboard SQL Editor:"
    echo "   https://supabase.com/dashboard/project/xnwieehlrhrffoikpglj/sql/new"
    exit 1
else
    echo "✅ All migrations applied successfully!"
fi
