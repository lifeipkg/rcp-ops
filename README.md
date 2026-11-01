# rcp-ops · 部署与迁移真源

平台运维仓：**迁移 SQL 的唯一真源**（红线 RL-004）+ K8s 部署形态 + 本地编排。

## 目录

| 路径 | 是什么 |
|---|---|
| `migrations/` | 版本化 DDL 真源，由 `rcp-db-ops` 执行；`V<版本>__<描述>.sql` 正向、`U<版本>__<描述>.sql` 回滚 |
| `k8s/` | 命名空间、配置、八个工作负载（网关 / 四条巡查线 / 数据网关 / 数据库操作 / 前端）、Ingress |
| `kustomization.yaml` | 入口：`kubectl apply -k .`；迁移 SQL 用 `configMapGenerator` 打进 db-ops 挂载点 |
| `docker-compose.yml` | 本地一键起全平台（含 MySQL） |

## 迁移版本

| 版本 | 内容 |
|---|---|
| `1.0.0` | 平台共同基建：幂等、状态机、规则、处置日志、复核队列、标注回流 |
| `1.1.0` | 内容巡查线：岗位状态机、指纹分段倒排、判重结果、岗位复核队列 |
| `1.2.0` | 消息巡查线：关键词库、变体映射、白名单、命中明细、消息幂等 |
| `1.3.0` | 平台级台账：`patrol_event` / `patrol_verdict`（dataway 白名单表的真源） |

> 命名冲突说明：`1.1.0` 里两张表原叫 `patrol_verdict` / `patrol_review_queue`，与 `1.0.0` 的通用复核队列同名。
> 版本化后改成 `job_verdict` / `job_review_queue`，语义边界明确（岗位判重专用 vs 平台通用）。

## 部署

```bash
# 集群
kubectl apply -k .
# 建库后执行迁移
curl -X POST http://db-ops:8091/dbops/migrate

# 本地
docker compose up --build
```

## 纪律

1. **DDL 只进 `migrations/`**，不接受"先在数据库手改、事后再补脚本"；
2. 每个版本**必须配对 undo 脚本**，否则回滚时 db-ops 会明确报 `IRREVERSIBLE_MIGRATION`；
3. 版本号按数字段递增（`1.10.0 > 1.9.0`）；
4. 部署清单里的镜像 tag 与 `kustomization.yaml` 的 `images` 保持同一次提交内一致；
5. 本仓不含业务逻辑，发现业务代码流进来就说明分层错了。
