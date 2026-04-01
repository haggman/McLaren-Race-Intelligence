-- McLaren Race Intelligence Platform
-- Pre-built BigQuery Views
--
-- These views transform raw F1 data into clean, self-documenting
-- analytical layers. They serve two purposes:
--   1. Human analysts can query McLaren performance without complex joins
--   2. The ADK agent generates dramatically better SQL against well-named
--      view columns than against raw tables with cryptic column names
--
-- All views derive McLaren's constructor_id dynamically via
-- WHERE constructor_ref = 'mclaren' — never hardcoded.
--
-- Dataset: f1_data (in the student's current project)

-- ============================================================
-- View 1: v_mclaren_race_results
-- The workhorse: one row per McLaren driver per race entry.
-- Includes race context, circuit context, driver info, result,
-- and pre-computed podium/win flags for easy aggregation.
-- ============================================================

CREATE OR REPLACE VIEW `f1_data.v_mclaren_race_results` AS

WITH mclaren_id AS (
  SELECT constructor_id
  FROM `f1_data.constructors`
  WHERE constructor_ref = 'mclaren'
)
SELECT
  -- Race context
  r.year                                              AS season,
  r.round                                             AS race_round,
  r.name                                              AS race_name,
  r.date                                              AS race_date,

  -- Circuit context
  c.name                                              AS circuit_name,
  c.circuit_ref                                       AS circuit_ref,
  c.location                                          AS circuit_location,
  c.country                                           AS circuit_country,

  -- Driver identity
  d.driver_ref                                        AS driver_ref,
  CONCAT(d.forename, ' ', d.surname)                  AS driver_name,
  d.nationality                                       AS driver_nationality,

  -- Race result
  res.grid                                            AS grid_position,
  res.position_order                                  AS finish_position,
  res.position_text                                   AS finish_position_text,
  res.points                                          AS points_scored,
  res.laps                                            AS laps_completed,

  -- Computed flags
  (res.position_order <= 3)                           AS is_podium,
  (res.position_order = 1)                            AS is_win,
  (res.position_order = 2)                            AS is_second,
  (res.position_order = 3)                            AS is_third,
  (res.position_text = 'R')                           AS is_retirement,

  -- Status (LEFT JOIN: view works even if status table is absent)
  st.status                                           AS race_status

FROM `f1_data.results` res
JOIN `f1_data.races` r         ON res.race_id = r.race_id
JOIN `f1_data.circuits` c      ON r.circuit_id = c.circuit_id
JOIN `f1_data.drivers` d       ON res.driver_id = d.driver_id
JOIN mclaren_id mc             ON res.constructor_id = mc.constructor_id
LEFT JOIN `f1_data.status` st  ON res.status_id = st.status_id
;


-- ============================================================
-- View 2: v_mclaren_qualifying
-- One row per McLaren driver per race qualifying session.
-- Includes all three qualifying segments and the furthest
-- segment reached. Join to v_mclaren_race_results on
-- (season, race_round, driver_ref) for quali-to-race analysis.
-- ============================================================

CREATE OR REPLACE VIEW `f1_data.v_mclaren_qualifying` AS

WITH mclaren_id AS (
  SELECT constructor_id
  FROM `f1_data.constructors`
  WHERE constructor_ref = 'mclaren'
)
SELECT
  -- Race context
  r.year                                              AS season,
  r.round                                             AS race_round,
  r.name                                              AS race_name,
  r.date                                              AS race_date,

  -- Circuit context
  c.name                                              AS circuit_name,
  c.circuit_ref                                       AS circuit_ref,
  c.country                                           AS circuit_country,

  -- Driver identity
  d.driver_ref                                        AS driver_ref,
  CONCAT(d.forename, ' ', d.surname)                  AS driver_name,

  -- Qualifying results
  q.position                                          AS qualifying_position,
  q.q1                                                AS q1_time,
  q.q2                                                AS q2_time,
  q.q3                                                AS q3_time,

  -- Which segment was the driver's final lap?
  CASE
    WHEN q.q3 IS NOT NULL THEN 'Q3'
    WHEN q.q2 IS NOT NULL THEN 'Q2'
    ELSE 'Q1'
  END                                                 AS furthest_qualifying_segment

FROM `f1_data.qualifying` q
JOIN `f1_data.races` r         ON q.race_id = r.race_id
JOIN `f1_data.circuits` c      ON r.circuit_id = c.circuit_id
JOIN `f1_data.drivers` d       ON q.driver_id = d.driver_id
JOIN mclaren_id mc             ON q.constructor_id = mc.constructor_id
;


-- ============================================================
-- View 3: v_mclaren_season_summary
-- One row per McLaren driver per season. All race-level detail
-- collapsed to season aggregates. Use for season comparison,
-- driver career progression, and "best season" queries.
-- Depends on: v_mclaren_race_results
-- ============================================================

CREATE OR REPLACE VIEW `f1_data.v_mclaren_season_summary` AS

SELECT
  season,
  driver_ref,
  driver_name,
  driver_nationality,

  COUNT(*)                                            AS races_entered,
  COUNTIF(is_win)                                     AS wins,
  COUNTIF(is_podium)                                  AS podiums,
  COUNTIF(finish_position <= 5)                       AS top_5_finishes,
  COUNTIF(finish_position <= 10)                      AS points_finishes,
  COUNTIF(is_retirement)                              AS retirements,

  SUM(points_scored)                                  AS total_points,
  ROUND(AVG(CAST(finish_position AS FLOAT64)), 2)     AS avg_finish_position,
  ROUND(AVG(CAST(grid_position AS FLOAT64)), 2)       AS avg_grid_position,

  -- Average places gained/lost per race (negative = gained places)
  ROUND(AVG(
    CAST(finish_position AS FLOAT64) - CAST(grid_position AS FLOAT64)
  ), 2)                                               AS avg_places_gained,

  MIN(finish_position)                                AS best_finish,
  MIN(grid_position)                                  AS best_qualifying_result

FROM `f1_data.v_mclaren_race_results`
GROUP BY season, driver_ref, driver_name, driver_nationality
;


-- ============================================================
-- View 4: v_mclaren_circuit_history
-- One row per circuit: McLaren's all-time record at that venue.
-- Use for pre-race narrative context and circuit-strength analysis.
-- Depends on: v_mclaren_race_results
-- ============================================================

CREATE OR REPLACE VIEW `f1_data.v_mclaren_circuit_history` AS

SELECT
  circuit_ref,
  circuit_name,
  circuit_location,
  circuit_country,

  COUNT(*)                                            AS total_race_entries,
  COUNT(DISTINCT season)                              AS seasons_raced,
  MIN(season)                                         AS first_season,
  MAX(season)                                         AS most_recent_season,

  COUNTIF(is_win)                                     AS wins,
  COUNTIF(is_podium)                                  AS podiums,
  COUNTIF(finish_position <= 5)                       AS top_5_finishes,

  ROUND(SAFE_DIVIDE(COUNTIF(is_win), COUNT(*)) * 100, 1)      AS win_rate_pct,
  ROUND(SAFE_DIVIDE(COUNTIF(is_podium), COUNT(*)) * 100, 1)   AS podium_rate_pct,

  ROUND(AVG(CAST(finish_position AS FLOAT64)), 2)     AS avg_finish_position,
  MIN(finish_position)                                AS best_finish_position

FROM `f1_data.v_mclaren_race_results`
GROUP BY circuit_ref, circuit_name, circuit_location, circuit_country
;


-- ============================================================
-- View 5: v_championship_progression
-- One row per race: McLaren's constructor championship standing
-- and cumulative points after each round. Includes the leader's
-- points for gap calculation. Filter by season for single-season
-- narrative arcs.
-- ============================================================

CREATE OR REPLACE VIEW `f1_data.v_championship_progression` AS

WITH mclaren_id AS (
  SELECT constructor_id
  FROM `f1_data.constructors`
  WHERE constructor_ref = 'mclaren'
),
mclaren_standings AS (
  SELECT
    cs.race_id,
    cs.points          AS mclaren_cumulative_points,
    cs.position        AS mclaren_championship_position,
    cs.wins            AS mclaren_cumulative_wins
  FROM `f1_data.constructor_standings` cs
  JOIN mclaren_id mc ON cs.constructor_id = mc.constructor_id
),
leader_points AS (
  SELECT
    race_id,
    MAX(points)        AS leader_cumulative_points
  FROM `f1_data.constructor_standings`
  GROUP BY race_id
)
SELECT
  r.year                                              AS season,
  r.round                                             AS race_round,
  r.name                                              AS race_name,
  r.date                                              AS race_date,
  c.name                                              AS circuit_name,
  c.country                                           AS circuit_country,

  ms.mclaren_championship_position,
  ms.mclaren_cumulative_points,
  ms.mclaren_cumulative_wins,
  lp.leader_cumulative_points,

  -- Points gap to leader (0 if McLaren IS the leader)
  (lp.leader_cumulative_points - ms.mclaren_cumulative_points)
                                                      AS points_gap_to_leader,

  -- Boolean: is McLaren leading the championship?
  (ms.mclaren_championship_position = 1)              AS is_championship_leader

FROM mclaren_standings ms
JOIN `f1_data.races` r         ON ms.race_id = r.race_id
JOIN `f1_data.circuits` c      ON r.circuit_id = c.circuit_id
JOIN leader_points lp          ON ms.race_id = lp.race_id
;


-- ============================================================
-- View 6: v_bqml_features
-- Feature engineering view for the podium prediction model.
-- One row per McLaren race entry with all model features and
-- the is_podium label.
--
-- Training data:  WHERE season <= 2023
-- Evaluation:     WHERE season >= 2024
--
-- All features use only pre-race information — no data leakage.
-- NULL handling via COALESCE for Round 1 / debut scenarios.
-- ============================================================

CREATE OR REPLACE VIEW `f1_data.v_bqml_features` AS

WITH mclaren_id AS (
  SELECT constructor_id
  FROM `f1_data.constructors`
  WHERE constructor_ref = 'mclaren'
),

-- Base McLaren race entries with race ordering
mclaren_base AS (
  SELECT
    res.result_id,
    res.race_id,
    res.driver_id,
    res.constructor_id,
    res.grid                                          AS grid_position,
    res.position_order                                AS finish_position,
    (res.position_order <= 3)                         AS is_podium,
    r.year                                            AS season,
    r.round                                           AS race_round,
    r.circuit_id,
    ROW_NUMBER() OVER (
      PARTITION BY res.driver_id ORDER BY r.date, r.round
    )                                                 AS driver_race_seq
  FROM `f1_data.results` res
  JOIN `f1_data.races` r       ON res.race_id = r.race_id
  JOIN mclaren_id mc           ON res.constructor_id = mc.constructor_id
  WHERE res.position_order IS NOT NULL
    AND res.position_order > 0
    AND res.grid IS NOT NULL
    AND res.grid > 0
),

-- Driver championship position AFTER each round
driver_standings_by_round AS (
  SELECT
    ds.driver_id,
    r.year                                            AS season,
    r.round                                           AS after_round,
    ds.position                                       AS championship_position
  FROM `f1_data.driver_standings` ds
  JOIN `f1_data.races` r ON ds.race_id = r.race_id
),

-- McLaren constructor championship position AFTER each round
constructor_standings_by_round AS (
  SELECT
    r.year                                            AS season,
    r.round                                           AS after_round,
    cs.position                                       AS championship_position
  FROM `f1_data.constructor_standings` cs
  JOIN `f1_data.races` r       ON cs.race_id = r.race_id
  JOIN mclaren_id mc           ON cs.constructor_id = mc.constructor_id
),

-- Driver historical avg finish at each circuit (PRIOR seasons only)
driver_circuit_history AS (
  SELECT
    a.driver_id,
    a.circuit_id,
    a.season                                          AS target_season,
    ROUND(AVG(CAST(b.finish_position AS FLOAT64)), 2) AS driver_avg_finish_at_circuit_prior,
    COUNT(b.result_id)                                AS driver_starts_at_circuit_prior
  FROM mclaren_base a
  LEFT JOIN mclaren_base b
    ON  a.driver_id  = b.driver_id
    AND a.circuit_id = b.circuit_id
    AND b.season     < a.season
  GROUP BY a.driver_id, a.circuit_id, a.season
),

-- McLaren podium rate at each circuit (PRIOR seasons only)
constructor_circuit_history AS (
  SELECT
    a.circuit_id,
    a.season                                          AS target_season,
    ROUND(
      SAFE_DIVIDE(COUNTIF(b.is_podium), COUNT(b.result_id)),
      3
    )                                                 AS mclaren_podium_rate_at_circuit_prior,
    COUNT(b.result_id)                                AS mclaren_entries_at_circuit_prior
  FROM (SELECT DISTINCT circuit_id, season FROM mclaren_base) a
  LEFT JOIN mclaren_base b
    ON  a.circuit_id = b.circuit_id
    AND b.season     < a.season
  GROUP BY a.circuit_id, a.season
),

-- Driver rolling avg finish over last 5 races (backward-looking only)
driver_rolling_form AS (
  SELECT
    result_id,
    driver_id,
    ROUND(
      AVG(CAST(finish_position AS FLOAT64)) OVER (
        PARTITION BY driver_id
        ORDER BY driver_race_seq
        ROWS BETWEEN 5 PRECEDING AND 1 PRECEDING
      ),
      2
    )                                                 AS driver_rolling_avg_finish_last5
  FROM mclaren_base
)

SELECT
  -- Identifiers (not model features)
  mb.result_id,
  mb.race_id,
  mb.driver_id,
  mb.circuit_id,
  mb.season,
  mb.race_round,

  -- === MODEL FEATURES (all pre-race information) ===

  mb.grid_position,

  COALESCE(
    dsb.championship_position,
    20
  )                                                   AS driver_championship_pos_entering,

  COALESCE(
    csb.championship_position,
    10
  )                                                   AS constructor_championship_pos_entering,

  COALESCE(
    dch.driver_avg_finish_at_circuit_prior,
    12.0
  )                                                   AS driver_avg_finish_at_circuit_prior,

  COALESCE(
    cch.mclaren_podium_rate_at_circuit_prior,
    0.15
  )                                                   AS mclaren_podium_rate_at_circuit_prior,

  COALESCE(
    drf.driver_rolling_avg_finish_last5,
    12.0
  )                                                   AS driver_rolling_avg_finish_last5,

  -- === LABEL ===
  mb.is_podium,

  -- === METADATA ===
  mb.finish_position

FROM mclaren_base mb

LEFT JOIN driver_standings_by_round dsb
  ON  mb.driver_id  = dsb.driver_id
  AND mb.season     = dsb.season
  AND mb.race_round = dsb.after_round + 1

LEFT JOIN constructor_standings_by_round csb
  ON  mb.season     = csb.season
  AND mb.race_round = csb.after_round + 1

LEFT JOIN driver_circuit_history dch
  ON  mb.driver_id  = dch.driver_id
  AND mb.circuit_id = dch.circuit_id
  AND mb.season     = dch.target_season

LEFT JOIN constructor_circuit_history cch
  ON  mb.circuit_id = cch.circuit_id
  AND mb.season     = cch.target_season

LEFT JOIN driver_rolling_form drf
  ON  mb.result_id  = drf.result_id
;
