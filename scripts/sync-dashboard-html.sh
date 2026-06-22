#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
INPUT="${ROOT_DIR}/dashboard/index.html"
OUTPUT="${ROOT_DIR}/src/base/api/DashboardHtml.h"

{
  printf '%s\n' '/* Generated from dashboard/index.html. Keep the editable source there. */'
  printf '%s\n' '#ifndef VELOXHASH_DASHBOARD_HTML_H'
  printf '%s\n' '#define VELOXHASH_DASHBOARD_HTML_H'
  printf '\n'
  printf '%s\n' 'namespace xmrig {'
  printf '\n'
  printf '%s\n' 'static const char *kDashboardHtml = R"VHX('
  sed 's/\r$//' "${INPUT}"
  printf '%s\n' ')VHX";'
  printf '\n'
  printf '%s\n' '} // namespace xmrig'
  printf '\n'
  printf '%s\n' '#endif // VELOXHASH_DASHBOARD_HTML_H'
} > "${OUTPUT}"

echo "Updated ${OUTPUT}"
