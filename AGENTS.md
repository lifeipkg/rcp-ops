# AGENTS.md · rcp-ops

本仓规则。工作区级流程见 `<工作区根>/AGENTS.md`。

## 本仓是什么

迁移真源 + 部署形态。命中**数据迁移**与**部署**两个高风险标签：任何迁移改动都要有回滚验证，
任何部署改动都要说明影响面。

## 硬约束

1. **迁移只增不改。** 已发布版本的脚本不得修改（改了等于篡改历史），修正走新版本。
2. **每个版本配 undo。** 缺少回滚脚本时 db-ops 会拒绝回滚；不要为了"先上线"省掉。
3. **不在本仓写业务代码。** 这里只有 SQL、清单与编排；业务逻辑回流说明分层破了。
4. **清单里的镜像 tag 与 kustomization 一致。** 两处漂移会让"部署的是哪版"无从核对。
5. **不提交真实凭据。** `k8s/02-secret.example.yaml` 只是形态示例，真实密码走集群注入；
   本地 `docker-compose.yml` 的口令走 gitignored 的 `.env`（模板 `.env.example`）。

## 验证

```bash
# 清单与迁移脚本可解析
python -c "import yaml,glob; [list(yaml.safe_load_all(open(f,encoding='utf-8'))) for f in glob.glob('**/*.yaml',recursive=True)]"

# 迁移版本与 undo 配对检查
python tools/check_migrations.py
```

改迁移时，除本仓检查外必须实跑一次 `db-ops` 的 `migrate` + `rollback`，只读代码不算验证。
