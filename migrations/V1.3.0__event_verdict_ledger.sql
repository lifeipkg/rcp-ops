-- ============================================================
-- 平台级事件与裁决台账（dataway 白名单表的真源）
--
-- 与 job_verdict 的区别：job_verdict 是内容巡查线的岗位判重明细，
-- 本表是**跨巡查线统一**的事件台账，字段即 PatrolEvent / PatrolVerdict 契约的落库形态。
-- ============================================================

CREATE TABLE patrol_event (
    event_id      VARCHAR(64)     NOT NULL COMMENT '事件ID: job:123 / msg:456 / acc:.. / fund:..',
    domain        VARCHAR(16)     NOT NULL COMMENT '巡查线: content/message/account/fund',
    version       BIGINT          NOT NULL DEFAULT 1 COMMENT '事件版本，单调递增',
    payload_json  JSON            NULL COMMENT '原始载荷，排障用',
    gmt_create    DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (event_id),
    KEY idx_domain_create (domain, gmt_create)
) ENGINE = InnoDB DEFAULT CHARSET = utf8mb4 COMMENT = '巡查事件台账';

CREATE TABLE patrol_verdict (
    id            BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
    event_id      VARCHAR(64)     NOT NULL,
    domain        VARCHAR(16)     NOT NULL,
    decision      VARCHAR(16)     NOT NULL COMMENT 'PASS/WARN/LIMIT/EXTRA_REVIEW/INTERCEPT/BAN',
    score         INT             NOT NULL DEFAULT 0 COMMENT '0-100 风险分',
    reason        VARCHAR(64)     NOT NULL DEFAULT '',
    degraded      TINYINT         NOT NULL DEFAULT 0 COMMENT '1=巡查线降级转加审',
    gmt_create    DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (id),
    KEY idx_event (event_id),
    KEY idx_domain_decision (domain, decision, gmt_create)
) ENGINE = InnoDB DEFAULT CHARSET = utf8mb4 COMMENT = '巡查裁决台账';
