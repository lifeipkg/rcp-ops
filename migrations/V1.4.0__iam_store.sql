-- ============================================================
-- Go 版 IAM（服务名 iam）的持久化表：用户与会话
--
-- DDL 只在 rcp-ops/migrations（RL-004）；iam 不直连数据库、不持驱动，
-- 读写只经 dataway 的 HTTP 契约（RL-005）：查询走 /dataway/query 的
-- 单条 SELECT，写入走 /dataway/execute 的服务端模板 ID。
--
-- PostgreSQL 方言差异见 V1.0.0__common_schema.sql 头部说明。
-- 用户名唯一由应用层先归一化为小写再写入，避免依赖表达式索引。
-- ============================================================

CREATE TABLE iam_users (
    user_id        VARCHAR(64)  NOT NULL,
    username       VARCHAR(64)  NOT NULL,
    display_name   VARCHAR(128) NOT NULL DEFAULT '',
    role           VARCHAR(16)  NOT NULL,
    status         VARCHAR(16)  NOT NULL DEFAULT 'ACTIVE',
    password_hash  VARCHAR(256) NOT NULL,
    password_salt  VARCHAR(128) NOT NULL,
    gmt_create     TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT pk_iam_users PRIMARY KEY (user_id),
    CONSTRAINT uk_iam_users_username UNIQUE (username)
);
COMMENT ON TABLE iam_users IS 'Go 版 IAM 用户表';
COMMENT ON COLUMN iam_users.role IS 'ADMIN / OPERATOR / VIEWER';
COMMENT ON COLUMN iam_users.status IS 'ACTIVE / DISABLED';
COMMENT ON COLUMN iam_users.password_hash IS 'PBKDF2-HmacSHA256，格式 iterations:base64';
COMMENT ON COLUMN iam_users.password_salt IS '每用户随机盐，base64';

CREATE TABLE iam_sessions (
    token       VARCHAR(128) NOT NULL,
    user_id     VARCHAR(64)  NOT NULL,
    expires_at  TIMESTAMP    NOT NULL,
    gmt_create  TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT pk_iam_sessions PRIMARY KEY (token)
);
CREATE INDEX idx_iam_sessions_user ON iam_sessions (user_id);
CREATE INDEX idx_iam_sessions_expires ON iam_sessions (expires_at);
COMMENT ON TABLE iam_sessions IS 'Go 版 IAM 不透明令牌会话';
COMMENT ON COLUMN iam_sessions.expires_at IS '过期时刻；内省时判 expires_at > CURRENT_TIMESTAMP';
