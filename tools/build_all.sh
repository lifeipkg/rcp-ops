#!/usr/bin/env bash
# 全量构建与机械检查。在工作区根目录执行：rcp-ops/tools/build_all.sh
#
# 顺序即依赖顺序：契约 → 本体 → 服务 → 前端 → 部署。
# 任一步失败立即退出，不做"后面的还能过就继续"。
set -euo pipefail

WS="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$WS"

if ! command -v go >/dev/null 2>&1; then
  echo "需要 Go 1.22+（构建全部 Go 服务）" >&2
  exit 2
fi

step() { printf '\n\033[1m== %s\033[0m\n' "$1"; }

step "契约 YAML 严格解析（含重复键）"
python rcp-ops/tools/check_manifests.py rcp-contracts

step "本体一致性（声明层 TTL / 契约 / 红线 / 仓布局）"
python rcp-ontology/checker/cli.py check --contracts rcp-contracts --workspace .

step "契约层静态检查（引用 / 破坏性变更）"
# 基线只在有远端时才对比：新仓或离线副本没有 origin/main，跳过而不是失败。
BASELINE=""
if git -C rcp-contracts rev-parse --verify -q origin/main >/dev/null 2>&1; then
  BASELINE="--baseline origin/main"
fi
python rcp-contracts/tools/contract_lint.py --contracts rcp-contracts $BASELINE

step "契约仓单元测试"
(cd rcp-contracts && python -m pytest -q tests)

step "本体单元测试"
(cd rcp-ontology && python -m pytest -q)

step "迁移版本配对"
python rcp-ops/tools/check_migrations.py

# Go 服务：rcp-iam 的 go.sum 尚未入库，由 tidy 生成；api-gateway / dataway / db-ops
# 的 go.sum 必须入库，故这里只做 verify（tidy 会改写依赖图，等于把校验变成自动修复）。
step "Go 服务 rcp-iam"
(cd rcp-iam && go mod tidy && go vet ./... && go test ./... && go build ./...)

GO_SERVICES=(
  rcp-api-gateway
  rcp-dataway
  rcp-db-ops
)

for repo in "${GO_SERVICES[@]}"; do
  step "Go 服务 $repo"
  (cd "$repo" && go mod verify && go vet ./... && go test ./... && go build ./...)
done

step "契约 → 实现 对表"
check_contract() {
  python rcp-contracts/tools/contract_check.py --repo "$1" --contract "rcp-contracts/contracts/openapi/$2"
}
check_contract rcp-api-gateway api-gateway.yaml
check_contract rcp-iam iam.yaml
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

step "部署清单严格解析（含重复键）"
python rcp-ops/tools/check_manifests.py rcp-ops

printf '\n\033[1;32m全部通过\033[0m\n'
