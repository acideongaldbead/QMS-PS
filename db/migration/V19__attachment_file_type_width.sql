-- ===========================================================================
-- V19 放宽 attachment.file_type（追加迁移）
-- ===========================================================================
-- 基线把 file_type 定为 varchar(32)，装得下 image/png (9)、application/pdf (15)、
-- video/mp4 (9) 这些短类型，但装不下 OOXML 的正式 MIME 类型：
--   Word    application/vnd.openxmlformats-officedocument.wordprocessingml.document  (68)
--   Excel   application/vnd.openxmlformats-officedocument.spreadsheetml.sheet        (64)
--   PPT     application/vnd.openxmlformats-officedocument.presentationml.presentation(73)
-- 后果不是「传不上去」而是**报一个与真实原因无关的错**：插入撞长度 →
-- DataIntegrityViolationException → 被 DataIntegrityTranslator 兜底成
-- 「数据校验未通过，请检查输入内容」。docx/xlsx 因此一直是「宣称支持、实际必挂」，
-- 直到为知识中心补 pptx 断言时才暴露出来。
--
-- 放宽到 varchar(128)：最长已知类型 73 字符，留出余量且不改变列的可空性。
-- ===========================================================================

SET search_path TO qms, public;

ALTER TABLE attachment ALTER COLUMN file_type TYPE varchar(128);

COMMENT ON COLUMN attachment.file_type IS '文件类型 | 嗅探出的 MIME 类型；OOXML 正式类型最长 73 字符，故为 varchar(128)（V19 放宽，原为 varchar(32)）';
