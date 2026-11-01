#!/usr/bin/env python3
"""严格解析 YAML：在"能解析"之外，额外拒绝重复键。

PyYAML 默认对重复键静默取后者——清单里写两个 ``env:`` 就会悄悄丢掉前一个，
而 ``safe_load`` 完全通过。这类错误不会在 CI 里暴露，只会在集群上表现为
"配置没生效"。本脚本把它变成可机械检出的失败。

用法：
    python tools/check_manifests.py rcp-contracts          # 契约仓
    python tools/check_manifests.py rcp-ops                # 部署清单

退出码：0 全部通过；1 有重复键或不可解析；2 输入缺失。
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

import yaml

SKIP_DIRS = {".git", ".agents", "target", "node_modules", "__pycache__"}


class StrictLoader(yaml.SafeLoader):
    """重复键即报错的 SafeLoader。"""


def _construct_mapping(loader: StrictLoader, node: yaml.MappingNode, deep: bool = False):
    seen: dict[object, int] = {}
    mapping = {}
    for key_node, value_node in node.value:
        key = loader.construct_object(key_node, deep=deep)
        if key in seen:
            raise yaml.constructor.ConstructorError(
                None,
                None,
                f"重复键 {key!r}（首次出现于第 {seen[key]} 行）",
                key_node.start_mark,
            )
        seen[key] = key_node.start_mark.line + 1
        mapping[key] = loader.construct_object(value_node, deep=deep)
    return mapping


StrictLoader.add_constructor(
    yaml.resolver.BaseResolver.DEFAULT_MAPPING_TAG, _construct_mapping
)


def yaml_files(root: Path) -> list[Path]:
    files: list[Path] = []
    for path in root.rglob("*"):
        if not path.is_file() or path.suffix not in {".yaml", ".yml"}:
            continue
        if SKIP_DIRS & set(path.parts):
            continue
        files.append(path)
    return sorted(files)


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="严格 YAML 校验（拒绝重复键）")
    parser.add_argument("paths", nargs="+", help="要检查的目录")
    args = parser.parse_args(argv)

    roots = [Path(item) for item in args.paths]
    missing = [str(root) for root in roots if not root.is_dir()]
    if missing:
        print(f"[check_manifests] 目录不存在: {', '.join(missing)}", file=sys.stderr)
        return 2

    total = 0
    failures: list[str] = []
    for root in roots:
        for path in yaml_files(root):
            total += 1
            try:
                list(yaml.load_all(path.read_text(encoding="utf-8"), Loader=StrictLoader))
            except yaml.YAMLError as exc:
                failures.append(f"{path.as_posix()}: {exc}")

    if failures:
        print("\n".join(failures))
        print(f"\n结论：{len(failures)} 个文件不可用（共 {total} 个）")
        return 1

    print(f"OK: {total} 个 YAML 严格解析通过（无重复键）")
    return 0


if __name__ == "__main__":
    sys.exit(main())
