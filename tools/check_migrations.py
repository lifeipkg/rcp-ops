#!/usr/bin/env python3
"""迁移脚本自检：版本配对、命名、重复。

只做机械检查：是不是每个 V 都有 U、版本号有没有重复、命名合不合约定。
脚本内容是否可执行由 db-ops 的实际 migrate/rollback 验证，这里不假装能判断。
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

DIR = Path(__file__).resolve().parent.parent / "migrations"
UP = re.compile(r"^V(\d+(?:\.\d+)*)__(.+)\.sql$")
DOWN = re.compile(r"^U(\d+(?:\.\d+)*)__(.+)\.sql$")


def main() -> int:
    if not DIR.is_dir():
        print(f"[check_migrations] 迁移目录不存在: {DIR}", file=sys.stderr)
        return 2

    ups: dict[str, str] = {}
    downs: dict[str, str] = {}
    errors: list[str] = []

    for file in sorted(DIR.glob("*.sql")):
        name = file.name
        m_up = UP.match(name)
        m_down = DOWN.match(name)
        if m_up:
            version = m_up.group(1)
            if version in ups:
                errors.append(f"版本重复: {version}（{ups[version]} 与 {name}）")
            ups[version] = name
        elif m_down:
            version = m_down.group(1)
            if version in downs:
                errors.append(f"回滚版本重复: {version}（{downs[version]} 与 {name}）")
            downs[version] = name
        else:
            errors.append(f"命名不合约定（应为 V<版本>__<描述>.sql / U<版本>__<描述>.sql）: {name}")

    for version, name in sorted(ups.items()):
        if version not in downs:
            errors.append(f"版本 {version} 缺少回滚脚本 U{version}__*.sql（{name}）")
        else:
            desc_up = UP.match(name).group(2)
            desc_down = DOWN.match(downs[version]).group(2)
            if desc_up != desc_down:
                errors.append(
                    f"版本 {version} 正/反向描述不一致: {desc_up} vs {desc_down}"
                )

    for version, name in sorted(downs.items()):
        if version not in ups:
            errors.append(f"回滚脚本没有对应正向版本: {name}")

    if errors:
        for error in errors:
            print(f"[ERROR] {error}")
        print(f"\n结论：{len(errors)} 个问题")
        return 1

    print(f"OK: {len(ups)} 个版本，正反向配对完整")
    for version in sorted(ups, key=lambda v: [int(p) for p in v.split(".")]):
        print(f"  V{version}  ←→  U{version}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
