#!/bin/bash
# Deploy all Supabase Edge Functions
# Usage: ./scripts/deploy_edge_functions.sh
#
# Prerequisites:
#   1. Install Supabase CLI: https://supabase.com/docs/guides/cli
#   2. Login: supabase login
#   3. Link project: supabase link --project-ref xnwieehlrhrffoikpglj
#
# This deploys all 8 edge functions to your Supabase project.

set -e

echo "=== Supabase Edge Function Deployment ==="
echo ""

# Check if supabase CLI is installed
if ! command -v supabase &> /dev/null; then
    echo "❌ Supabase CLI not found."
    echo "   Install it from: https://supabase.com/docs/guides/cli/getting-started"
    exit 1
fi

# Check if linked
echo "Linking to project xnwieehlrhrffoikpglj..."
supabase link --project-ref xnwieehlrhrffoikpglj || true

echo ""
echo "Deploying edge functions..."
echo ""

FUNCTIONS=(
    "admin-wallet-recharge"
    "order-create"
    "order-transition"
    "provider-approval"
    "ride-claim"
    "ride-transition"
    "subscription-process"
    "wallet-deduct-fee"
)

DEPLOYED=0
FAILED=0

for func in "${FUNCTIONS[@]}"; do
    echo -n "  Deploying $func... "
    
    if supabase functions deploy "$func" 2>/dev/null; then
        echo "✅"
        DEPLOYED=$((DEPLOYED + 1))
    else
        echo "❌ FAILED"
        FAILED=$((FAILED + 1))
    fi
done

echo ""
echo "=== Summary ==="
echo "  Deployed: $DEPLOYED/${#FUNCTIONS[@]}"
echo "  Failed: $FAILED"
echo ""

if [ $FAILED -gt 0 ]; then
    echo "⚠️  Some functions failed to deploy. Check the output above."
    exit 1
else
    echo "✅ All edge functions deployed successfully!"
    echo ""
    echo "Functions are now callable at:"
    for func in "${FUNCTIONS[@]}"; do
        echo "  https://xnwieehlrhrffoikpglj.supabase.co/functions/v1/$func"
    done
fi
