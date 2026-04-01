-- McLaren Race Intelligence Platform
-- BQML Model Evaluation Queries
--
-- Run these after create_model.sql completes training.
-- Each query is separated by a blank line for readability.
-- Run them individually in BigQuery Studio or sequentially via bq query.

-- ============================================================
-- 1. Model Evaluation Metrics
-- Key metrics: precision, recall, roc_auc
-- Target: roc_auc > 0.80 indicates solid discriminative ability
-- ============================================================

SELECT *
FROM ML.EVALUATE(MODEL `f1_data.podium_predictor`);


-- ============================================================
-- 2. Feature Importance
-- Shows which variables drive the prediction.
-- Expected: grid_position dominates; circuit history and
-- recent form provide secondary signal.
-- ============================================================

SELECT *
FROM ML.FEATURE_IMPORTANCE(MODEL `f1_data.podium_predictor`)
ORDER BY importance_gain DESC;


-- ============================================================
-- 3. Confusion Matrix
-- Shows exactly where the model makes mistakes.
-- More informative for a live demo than aggregate metrics.
-- ============================================================

SELECT *
FROM ML.CONFUSION_MATRIX(MODEL `f1_data.podium_predictor`);
