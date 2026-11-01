-- ============================================================
-- 风控巡查平台 - 共同基建 MySQL 表结构（演示）
--
-- 四条巡查线共用底座：幂等 / 状态机 / 规则 / 处置 / 复核 / 标注回流
-- ============================================================

-- 消费幂等表（Kafka 统一幂等：event_id + version，重复消费拒绝旧版本）
CREATE TABLE patrol_idempotent (
    event_id      VARCHAR(64)     NOT NULL COMMENT '事件ID: job:123 / msg:456 / fund:789',
    domain        VARCHAR(16)     NOT NULL COMMENT '巡查线: content/message/account/fund',
    version       BIGINT          NOT NULL DEFAULT 0,
    gmt_create    DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (event_id),
    KEY idx_domain (domain, gmt_create)
) ENGINE = InnoDB DEFAULT CHARSET = utf8mb4 COMMENT = '巡查消费幂等';

-- 巡查对象统一状态机（version + 单调状态，防乱序消息导致状态回跳）
CREATE TABLE patrol_object_state (
    event_id      VARCHAR(64)     NOT NULL COMMENT '对象ID',
    domain        VARCHAR(16)     NOT NULL,
    status        TINYINT         NOT NULL COMMENT '0待审 1通过 2疑似(人审) 3拦截 4封禁 5申诉中',
    version       BIGINT          NOT NULL DEFAULT 0 COMMENT '版本号，只允许前进',
    gmt_modified  DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (event_id),
    KEY idx_domain_status (domain, status)
) ENGINE = InnoDB DEFAULT CHARSET = utf8mb4 COMMENT = '巡查对象状态机';

-- 风控规则表（热更新，规则快照原子切换）
CREATE TABLE patrol_rule (
    id            BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
    rule_key      VARCHAR(64)     NOT NULL COMMENT '规则标识',
    priority      INT             NOT NULL DEFAULT 100 COMMENT '越小越优先，短路求值',
    enabled       TINYINT         NOT NULL DEFAULT 1,
    rule_json     JSON            NOT NULL COMMENT '条件树(字段/操作符/值 AND 组合)',
    decision      VARCHAR(16)     NOT NULL COMMENT 'PASS/LIMIT/EXTRA_REVIEW/INTERCEPT/BAN',
    reason        VARCHAR(32)     NOT NULL,
    gmt_modified  DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (id),
    UNIQUE KEY uk_rule_key (rule_key)
) ENGINE = InnoDB DEFAULT CHARSET = utf8mb4 COMMENT = '风控规则';

-- 处置流水（分级处置：同一决策对不同对象的落地动作不同）
CREATE TABLE patrol_action_log (
    id            BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
    event_id      VARCHAR(64)     NOT NULL,
    domain        VARCHAR(16)     NOT NULL,
    decision      VARCHAR(16)     NOT NULL,
    action        VARCHAR(32)     NOT NULL COMMENT '落地动作: HIDE/LIMIT_POST/REVIEW/BLOCK/RECALL_GRANT',
    operator      VARCHAR(32)     NOT NULL DEFAULT 'SYSTEM' COMMENT 'SYSTEM=自动, 否则人审员工号',
    gmt_create    DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (id),
    KEY idx_event (event_id),
    KEY idx_domain_time (domain, gmt_create)
) ENGINE = InnoDB DEFAULT CHARSET = utf8mb4 COMMENT = '处置流水';

-- 人工复核队列（各巡查线疑似样本统一入口）
CREATE TABLE patrol_review_queue (
    id            BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
    event_id      VARCHAR(64)     NOT NULL,
    domain        VARCHAR(16)     NOT NULL,
    reason        VARCHAR(32)     NOT NULL COMMENT '进入原因: 疑似/评分区间/申诉',
    assignee      VARCHAR(32)     NULL COMMENT '人审员工号',
    review_status TINYINT         NOT NULL DEFAULT 0 COMMENT '0待审 1确认违规 2误杀 3升级',
    reviewed_by   VARCHAR(32)     NULL,
    gmt_create    DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (id),
    KEY idx_domain_status (domain, review_status, gmt_create)
) ENGINE = InnoDB DEFAULT CHARSET = utf8mb4 COMMENT = '人工复核队列';

-- 标注回流表（误杀/漏放样本回流：驱动关键词库、变体映射、阈值再标定）
CREATE TABLE patrol_feedback (
    id            BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
    review_id     BIGINT UNSIGNED NOT NULL COMMENT '来源复核单',
    domain        VARCHAR(16)     NOT NULL,
    label         VARCHAR(16)     NOT NULL COMMENT 'FALSE_KILL误杀 / MISSED漏放',
    payload       JSON            NULL COMMENT '样本特征快照',
    consumed      TINYINT         NOT NULL DEFAULT 0 COMMENT '0未消费 1已回流到词库/阈值',
    gmt_create    DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (id),
    KEY idx_consumed (consumed, domain)
) ENGINE = InnoDB DEFAULT CHARSET = utf8mb4 COMMENT = '标注回流';

-- Kafka Topic 规划（统一事件总线，patrol.{domain}.{event}）
--   patrol.content.publish    岗位发布/更新    -> 内容巡查线 (job-patrol-system)
--   patrol.im.message         IM 消息发送      -> 消息巡查线 (message-patrol)
--   patrol.account.register   注册/登录        -> 账号巡查线
--   patrol.fund.grant         补贴发放申请      -> 资金巡查线
