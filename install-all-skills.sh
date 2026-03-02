#!/bin/bash
# =============================================================================
# install-all-skills.sh — Install all skills to ~/.claude/skills/
# Usage: cd ~/Desktop/GEMS/dev/SKILLS && bash install-all-skills.sh
# =============================================================================

set -e

REPO_DIR="$(cd "$(dirname "$0")" && pwd)"
DEST="$HOME/.claude/skills"

echo ""
echo "╔══════════════════════════════════════════════════╗"
echo "║   Skills Installer — Claude Code (Copilot CLI)  ║"
echo "╚══════════════════════════════════════════════════╝"
echo ""
echo "  Source: $REPO_DIR"
echo "  Target: $DEST"
echo ""

mkdir -p "$DEST"

install_skill() {
  local name="$1"
  local src="$REPO_DIR/$name"

  if [ ! -d "$src" ]; then
    echo "  ⚠ SKIP  $name (not found)"
    return
  fi

  mkdir -p "$DEST/$name"

  if [ -f "$src/SKILL.md" ]; then
    cp "$src/SKILL.md" "$DEST/$name/"
  fi

  if [ -d "$src/references" ]; then
    mkdir -p "$DEST/$name/references"
    cp "$src/references/"* "$DEST/$name/references/" 2>/dev/null || true
  fi

  local ref_count=$(ls "$DEST/$name/references/" 2>/dev/null | wc -l | tr -d ' ')
  echo "  ✅ $name  (SKILL.md + $ref_count refs)"
}

# --- Enterprise Skills ---
echo "━━━ Enterprise Skills ━━━"
ENTERPRISE_SKILLS=(
  "enterprise-AI-applications"
  "enterprise-AI-foundations"
  "enterprise-AI-fundamentals"
  "enterprise-backend"
  "enterprise-data-analytics"
  "enterprise-database"
  "enterprise-deployment"
  "enterprise-devx-monorepo"
  "enterprise-frontend"
  "enterprise-i18n-accessibility"
  "enterprise-mobile"
  "enterprise-search-messaging"
  "enterprise-security"
  "enterprise-testing"
)

for skill in "${ENTERPRISE_SKILLS[@]}"; do
  install_skill "$skill"
done

# --- Specialty Skills ---
echo ""
echo "━━━ Specialty Skills ━━━"
install_skill "skill-self-improving"

echo "  → postmark (multi-skill suite)"
cp -R "$REPO_DIR/postmark" "$DEST/" 2>/dev/null || true
sub_count=$(find "$DEST/postmark" -name "SKILL.md" | wc -l | tr -d ' ')
echo "  ✅ postmark  ($sub_count sub-skills)"

# --- Utility Skills ---
echo ""
echo "━━━ Utility Skills ━━━"
UTILITY_SKILLS=(
  "deployment-validator"
  "env-config-auditor"
  "pre-deploy-security-scanner"
  "session-orchestrator"
)

for skill in "${UTILITY_SKILLS[@]}"; do
  install_skill "$skill"
done

# --- Summary ---
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
total_dirs=$(ls -d "$DEST"/*/ 2>/dev/null | wc -l | tr -d ' ')
total_refs=$(find "$DEST" -name "*.md" -path "*/references/*" 2>/dev/null | wc -l | tr -d ' ')
total_skills=$(find "$DEST" -name "SKILL.md" 2>/dev/null | wc -l | tr -d ' ')
echo "  📦 $total_dirs skill directories installed"
echo "  📄 $total_skills SKILL.md files"
echo "  📚 $total_refs reference documents"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "✅ Done! Skills are ready in $DEST"
echo ""
