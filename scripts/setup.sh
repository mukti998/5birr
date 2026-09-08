#!/usr/bin/env bash
set -euo pipefail

# 5BIRR — Local development setup script
# Run this once after cloning the repo.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

cd "$REPO_ROOT"

echo "============================================"
echo "  5BIRR — Local Setup"
echo "============================================"
echo ""

# --- Check for Flutter ---
if ! command -v flutter &>/dev/null; then
  echo "ERROR: Flutter SDK is not installed or not on your PATH."
  echo ""
  echo "Install Flutter by following the official guide:"
  echo "  https://docs.flutter.dev/get-started/install"
  echo ""
  echo "After installing, run 'flutter doctor' to verify your setup,"
  echo "then re-run this script."
  exit 1
fi

echo "Flutter found: $(flutter --version | head -1)"
echo ""

# --- Install Dart/Flutter dependencies ---
echo "Running flutter pub get ..."
flutter pub get
echo ""

# --- Create .env.example from the template if it doesn't exist ---
if [ ! -f .env.example ]; then
  if [ -f env.example.txt ]; then
    cp env.example.txt .env.example
    echo "Created .env.example from env.example.txt"
  else
    echo "WARNING: env.example.txt not found — skipping .env.example creation."
  fi
else
  echo ".env.example already exists — skipping."
fi
echo ""

# --- Remind about .env ---
echo "============================================"
echo "  Next steps:"
echo "  1. Copy .env.example to .env"
echo "  2. Fill in your real Supabase URL, anon key,"
echo "     service role key, and other secrets."
echo "  3. Run 'flutter run' to start the app."
echo "============================================"
