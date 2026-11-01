-- 回滚 V1.0.0：逆序删表（先删有关联语义的，再删主表）
DROP TABLE IF EXISTS patrol_feedback;
DROP TABLE IF EXISTS patrol_review_queue;
DROP TABLE IF EXISTS patrol_action_log;
DROP TABLE IF EXISTS patrol_rule;
DROP TABLE IF EXISTS patrol_object_state;
DROP TABLE IF EXISTS patrol_idempotent;
