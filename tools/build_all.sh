#!/usr/bin/env bash
# 全量构建与机械检查。在工作区根目录执行：rcp-ops/tools/build_all.sh
#
# 顺序即依赖顺序：契约 → 本体 → 基座 → 服务 → 网关 → 数据层 → 前端 → 部署。
# 任一步失败立即退出，不做"后面的还能过就继续"。
set -euo pipefail

WS="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$WS"

if [[ -z "${JAVA_HOME:-}" ]]; then
  echo "需要 JAVA_HOME（JDK 17）" >&2
  exit 2
fi
MVN="${MVN:-mvn}"

step() { printf '\n\033[1m== %s\033[0m\n' "$1"; }

step "契约 YAML 可解析"
python - <<'PY'
import glob, sys, yaml
bad = []
for f in sorted(glob.glob('rcp-contracts/**/*.yaml', recursive=True) + glob.glob('rcp-contracts/**/*.yml', recursive=True)):
    try:
        list(yaml.safe_load_all(open(f, encoding='utf-8')))
    except Exception as exc:
        bad.append(f'{f}: {exc}')
if bad:
    print('\n'.join(bad))
    sys.exit(1)
print(f'OK: {len(glob.glob("rcp-contracts/**/*.yaml", recursive=True))} 个 YAML')
PY

step "本体一致性（登记 / 契约 / 红线）"
python rcp-ontology/rcp_ontology/cli.py check --contracts rcp-contracts

step "本体单元测试"
(cd rcp-ontology && python -m pytest -q)

step "迁移版本配对"
python rcp-ops/tools/check_migrations.py

step "基座 rcp-core"
(cd rcp-core && "$MVN" -B -q install)

JAVA_SERVICES=(
  rcp-api-gateway
  rcp-content-patrol
  rcp-message-patrol
  rcp-account-patrol
  rcp-fund-patrol
  rcp-dataway
  rcp-db-ops
)

for repo in "${JAVA_SERVICES[@]}"; do
  step "$repo"
  (cd "$repo" && "$MVN" -B -q verify)
done

step "契约 → 实现 对表"
check_contract() {
  python rcp-contracts/tools/contract_check.py --repo "$1" --contract "rcp-contracts/contracts/openapi/$2"
}
check_contract rcp-api-gateway api-gateway.yaml
check_contract rcp-content-patrol content-patrol.yaml
check_contract rcp-message-patrol message-patrol.yaml
check_contract rcp-account-patrol account-patrol.yaml
check_contract rcp-fund-patrol fund-patrol.yaml
check_contract rcp-dataway dataway.yaml
check_contract rcp-db-ops db-ops.yaml

step "前端静态引用"
python - <<'PY'
import re, sys
from pathlib import Path
html = Path('rcp-web/index.html').read_text(encoding='utf-8')
refs = re.findall(r'(?:href|src)="([^"#:]+)"', html)
missing = [r for r in refs if not (Path('rcp-web') / r).is_file()]
if missing:
    print('缺失:', missing)
    sys.exit(1)
print('OK: 引用齐全', refs)
PY

step "部署清单可解析"
python - <<'PY'
import glob, sys, yaml
bad = []
for f in sorted(glob.glob('rcp-ops/**/*.yaml', recursive=True) + glob.glob('rcp-ops/**/*.yml', recursive=True)):
    try:
        list(yaml.safe_load_all(open(f, encoding='utf-8')))
    except Exception as exc:
        bad.append(f'{f}: {exc}')
if bad:
    print('\n'.join(bad))
    sys.exit(1)
print('OK: 清单全部可解析')
PY

printf '\n\033[1;32m全部通过\033[0m\n'
