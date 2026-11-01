-- ============================================================
-- 岗位巡查系统 - MySQL 生产化表结构（演示）
--
-- 设计要点：
--   1. 指纹段倒排表：64bit 指纹拆 4 段各 16bit，每段一行，
--      依据抽屉原理，汉明距离 <= 3 的指纹必共享至少一段；
--   2. 联合索引 (shard_key, seg_idx, seg_val) 支撑"分片内段等值查询"；
--   3. 30 天滑动窗口：过期数据由定时任务清理，控制倒排规模与桶倾斜；
--   4. 岗位状态机表：version 字段 + 单调状态，防 Kafka 重复消费导致状态回跳。
-- ============================================================

-- 岗位状态机表
CREATE TABLE job_patrol_state (
    id            BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
    job_id        BIGINT UNSIGNED NOT NULL COMMENT '岗位ID',
    shard_key     VARCHAR(64)     NOT NULL COMMENT '分片键: city|trade',
    status        TINYINT         NOT NULL COMMENT '状态: 0待审 1通过 2疑似重复(复核) 3驳回 4下架',
    version       BIGINT          NOT NULL DEFAULT 0 COMMENT '版本号，幂等写入/单调性约束用',
    reason        VARCHAR(32)     NULL COMMENT '判定来源: SIMHASH_BODY / TITLE_EDIT_DISTANCE / MANUAL',
    gmt_create    DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP,
    gmt_modified  DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (id),
    UNIQUE KEY uk_job (job_id),
    KEY idx_shard_status (shard_key, status)
) ENGINE = InnoDB DEFAULT CHARSET = utf8mb4 COMMENT = '岗位巡查状态机';

-- 指纹段倒排表（每个指纹写 4 行）
CREATE TABLE job_fingerprint_seg (
    id            BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
    job_id        BIGINT UNSIGNED NOT NULL COMMENT '岗位ID',
    shard_key     VARCHAR(64)     NOT NULL COMMENT '分片键: city|trade',
    seg_idx       TINYINT         NOT NULL COMMENT '段序号 0-3',
    seg_val       INT UNSIGNED    NOT NULL COMMENT '该段16bit值(0-65535)',
    fingerprint   BIGINT UNSIGNED NOT NULL COMMENT '完整64bit指纹',
    publish_time  DATETIME        NOT NULL COMMENT '发布时间，滑动窗口清理依据',
    PRIMARY KEY (id),
    UNIQUE KEY uk_job_seg (job_id, seg_idx),
    KEY idx_lookup (shard_key, seg_idx, seg_val, publish_time)
) ENGINE = InnoDB DEFAULT CHARSET = utf8mb4 COMMENT = 'SimHash 指纹段倒排';

-- 判重结果幂等表（Kafka 消费幂等：job_id + 版本号）
CREATE TABLE job_verdict (
    id            BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
    job_id        BIGINT UNSIGNED NOT NULL,
    version       BIGINT          NOT NULL COMMENT '岗位版本号，重复消费时拒绝旧版本',
    duplicate     TINYINT         NOT NULL,
    matched_job   BIGINT UNSIGNED NULL COMMENT '命中的已存在岗位',
    body_hamming  INT             NULL COMMENT '正文最小汉明距离',
    title_edit    INT             NULL COMMENT '标题编辑距离',
    gmt_create    DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (id),
    UNIQUE KEY uk_job_version (job_id, version)
) ENGINE = InnoDB DEFAULT CHARSET = utf8mb4 COMMENT = '岗位判重结果(幂等)';

-- 人工复核队列
CREATE TABLE job_review_queue (
    id            BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
    job_id        BIGINT UNSIGNED NOT NULL,
    matched_job   BIGINT UNSIGNED NOT NULL COMMENT '相似的原岗位',
    body_hamming  INT             NOT NULL COMMENT '两岗位指纹汉明距离',
    status        TINYINT         NOT NULL DEFAULT 0 COMMENT '0待复核 1确认重复 2误杀(回流标注集)',
    gmt_create    DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (id),
    KEY idx_status (status, gmt_create)
) ENGINE = InnoDB DEFAULT CHARSET = utf8mb4 COMMENT = '疑似重复岗位人工复核队列';

-- 典型查询：候选集召回（对应 SegmentIndex.candidates）
--   SELECT job_id, fingerprint
--   FROM job_fingerprint_seg FORCE INDEX (idx_lookup)
--   WHERE shard_key = '重庆|钢筋工'
--     AND publish_time >= NOW() - INTERVAL 30 DAY
--     AND ((seg_idx = 0 AND seg_val = ?)
--       OR (seg_idx = 1 AND seg_val = ?)
--       OR (seg_idx = 2 AND seg_val = ?)
--       OR (seg_idx = 3 AND seg_val = ?));
