-- ============================================================
-- 消息巡查（飞单治理）- MySQL 生产化表结构（演示）
-- ============================================================

-- 敏感关键词库（标准词空间，AC 自动机数据源，双缓冲热更新）
CREATE TABLE patrol_keyword (
    id            BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
    keyword       VARCHAR(128)    NOT NULL COMMENT '标准词（归一化后的形态）',
    category      VARCHAR(32)     NOT NULL COMMENT '分类: 飞单/资金/收费/其他',
    risk_level    TINYINT         NOT NULL DEFAULT 1 COMMENT '风险等级 1低 2中 3高',
    enabled       TINYINT         NOT NULL DEFAULT 1,
    source        VARCHAR(16)     NOT NULL DEFAULT 'MANUAL' COMMENT '来源: MANUAL/REVIEW回流',
    gmt_create    DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP,
    gmt_modified  DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (id),
    UNIQUE KEY uk_keyword (keyword)
) ENGINE = InnoDB DEFAULT CHARSET = utf8mb4 COMMENT = '巡查关键词库';

-- 变体映射表（薇芯/vx/威信 -> 微信，人审回流持续补充）
CREATE TABLE patrol_variant_map (
    id            BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
    variant       VARCHAR(128)    NOT NULL COMMENT '变体（归一化后形态）',
    canonical     VARCHAR(128)    NOT NULL COMMENT '标准词',
    source        VARCHAR(16)     NOT NULL DEFAULT 'MANUAL',
    enabled       TINYINT         NOT NULL DEFAULT 1,
    gmt_create    DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (id),
    UNIQUE KEY uk_variant (variant)
) ENGINE = InnoDB DEFAULT CHARSET = utf8mb4 COMMENT = '对抗变体映射';

-- 白名单（官方渠道话术，避免误杀）
CREATE TABLE patrol_whitelist (
    id            BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
    phrase        VARCHAR(128)    NOT NULL,
    enabled       TINYINT         NOT NULL DEFAULT 1,
    gmt_create    DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (id),
    UNIQUE KEY uk_phrase (phrase)
) ENGINE = InnoDB DEFAULT CHARSET = utf8mb4 COMMENT = '巡查白名单';

-- 命中记录（供人审工作台与指标统计）
CREATE TABLE patrol_message_hit (
    id            BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
    message_id    BIGINT UNSIGNED NOT NULL,
    session_id    BIGINT UNSIGNED NOT NULL COMMENT '会话ID',
    sender_id     BIGINT UNSIGNED NOT NULL,
    sender_role   TINYINT         NOT NULL COMMENT '0求职者 1招聘者',
    decision      TINYINT         NOT NULL COMMENT '0放行 1提示 2拦截',
    reason        VARCHAR(32)     NOT NULL,
    hit_words     VARCHAR(512)    NOT NULL COMMENT '命中词，逗号分隔',
    content_snapshot VARCHAR(1024) NOT NULL COMMENT '原文快照(脱敏)',
    review_status TINYINT         NOT NULL DEFAULT 0 COMMENT '0待人审 1确认 2误杀',
    gmt_create    DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (id),
    KEY idx_review (review_status, gmt_create),
    KEY idx_sender (sender_id, gmt_create)
) ENGINE = InnoDB DEFAULT CHARSET = utf8mb4 COMMENT = '消息巡查命中记录';

-- Kafka 消费幂等表（消息 ID + 处理版本，防重复消费）
CREATE TABLE patrol_message_idempotent (
    message_id    BIGINT UNSIGNED NOT NULL,
    version       BIGINT          NOT NULL DEFAULT 0,
    gmt_create    DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (message_id)
) ENGINE = InnoDB DEFAULT CHARSET = utf8mb4 COMMENT = '消息巡查消费幂等';
