-- McLaren Race Intelligence Platform
-- BQML Podium Prediction Model
--
-- Logistic regression trained on McLaren race entries through 2023.
-- Target: is_podium (boolean) — did the driver finish in the top 3?
-- Holdout: 2024+ seasons reserved for prediction demonstrations.
--
-- Training data: ~2,500–3,000 rows (McLaren entries with valid grid positions)
-- Training time: ~1–2 minutes
--
-- Features use only pre-race information to avoid data leakage:
--   - grid_position: Starting position (strongest single predictor)
--   - driver_championship_pos_entering: Driver momentum this season
--   - constructor_championship_pos_entering: Team competitiveness this season
--   - driver_avg_finish_at_circuit_prior: Driver-specific circuit affinity
--   - mclaren_podium_rate_at_circuit_prior: Team's historical circuit strength
--   - driver_rolling_avg_finish_last5: Recent form over last 5 races

CREATE OR REPLACE MODEL `f1_data.podium_predictor`
OPTIONS(
  model_type               = 'LOGISTIC_REG',
  input_label_cols         = ['is_podium'],
  data_split_method        = 'RANDOM',
  data_split_eval_fraction = 0.15,
  l2_reg                   = 0.1
)
AS
SELECT
  -- Features
  grid_position,
  driver_championship_pos_entering,
  constructor_championship_pos_entering,
  driver_avg_finish_at_circuit_prior,
  mclaren_podium_rate_at_circuit_prior,
  driver_rolling_avg_finish_last5,

  -- Label
  is_podium

FROM `f1_data.v_bqml_features`
WHERE season <= 2023
  AND grid_position IS NOT NULL
;
