-- 回滚 V1.2.0：消息巡查线表
DROP TABLE IF EXISTS patrol_message_idempotent;
DROP TABLE IF EXISTS patrol_message_hit;
DROP TABLE IF EXISTS patrol_whitelist;
DROP TABLE IF EXISTS patrol_variant_map;
DROP TABLE IF EXISTS patrol_keyword;
