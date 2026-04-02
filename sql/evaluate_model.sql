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
-- 2. Model Weights
-- Shows the learned coefficient for each feature.
-- Larger absolute values = stronger influence on prediction.
-- Negative weight = higher values reduce podium probability.
-- Expected: grid_position has the largest negative weight
-- (worse starting position = fewer podiums).
-- ============================================================

SELECT *
FROM ML.WEIGHTS(MODEL `f1_data.podium_predictor`)
ORDER BY ABS(weight) DESC;


-- ============================================================
-- 3. Confusion Matrix
-- Shows exactly where the model makes mistakes.
-- More informative for a live demo than aggregate metrics.
-- ============================================================

SELECT *
FROM ML.CONFUSION_MATRIX(MODEL `f1_data.podium_predictor`);
