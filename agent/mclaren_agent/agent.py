"""
McLaren Race Intelligence Platform — ADK Agent
================================================
The data science tier of the McLaren Race Intelligence Platform.
 
This agent provides programmatic access to BigQuery race data, a BQML
podium prediction model, and data visualization — capabilities that
Gemini Enterprise and Agent Designer cannot provide because they are
retrieval systems, not computation systems.
 
Architecture:
    root_agent (mclaren_race_intelligence)
        ├── BigQueryToolset  — query F1 data via ADK's built-in BQ tools
        ├── get_podium_predictions() — run BQML inference
        └── AgentTool(visualization_agent) — generate charts with Python
            └── BuiltInCodeExecutor
"""

import os
import google.auth
from google.adk.agents import Agent
from google.adk.tools.agent_tool import AgentTool
from google.adk.tools.bigquery import BigQueryCredentialsConfig, BigQueryToolset
from google.adk.code_executors import BuiltInCodeExecutor
from google.cloud import bigquery
from google.genai import types

from .prompts import (
    ROOT_AGENT_DESCRIPTION,
    get_root_agent_instructions,
    VISUALIZATION_AGENT_DESCRIPTION,
    VISUALIZATION_INSTRUCTIONS,
)

# ============================================================================
# Configuration
# ============================================================================
PROJECT_ID = os.environ.get("PROJECT_ID")
LOCATION = os.environ.get("REGION", "us-central1")

# ============================================================================
# Enable Provisioned Throughput (where applicable)
# ============================================================================
shared_config = types.GenerateContentConfig(
    http_options=types.HttpOptions(
        api_version="v1",
        headers={"X-Vertex-AI-LLM-Request-Type": "shared"},
        retry_options=types.HttpRetryOptions(
            attempts=10,
            initial_delay=0.5,      # start fast
            max_delay=4.0,          # cap each wait at 4s
            exp_base=2.0,           # doubles until capped
            jitter=1.0,             # avoid thundering-herd retries
            http_status_codes=[408, 429, 500, 502, 503, 504],
        ),
    ),
)

# ============================================================================
# TODO 1 — Connect to BigQuery using ADK's Built-in BigQueryToolset
# ============================================================================

bigquery_toolset = None  # TODO 1: Replace with BigQueryToolset setup


# ============================================================================
# BQML Podium Prediction Tool (pre-built — read, don't modify)
# ============================================================================
#
# This function runs ML.PREDICT against the podium_predictor model you
# trained in Task 2. It's provided complete so you can focus on the ADK
# architecture concepts in the TODOs above and below.
#
# Key things to notice in this code:
#   - It uses the BigQuery Python client directly (not the BigQueryToolset)
#     because the ML.PREDICT query is complex and we want guaranteed-correct
#     SQL rather than relying on the LLM to generate it
#   - The UNNEST pattern extracts podium probability from the BQML output
#   - It compares predictions to actual results and computes accuracy stats
#   - The model was trained through 2023, so 2024+ is genuinely out-of-sample
#
def get_podium_predictions(season: int = 2024) -> dict:
    """Run the BQML podium prediction model for a given season.

    Executes ML.PREDICT against the podium_predictor model using pre-race
    features, then compares predictions to actual results. The model was
    trained on data through 2023, so any season >= 2024 represents true
    out-of-sample prediction.

    Args:
        season: The season year to predict. Default 2024.

    Returns:
        A dict with 'predictions' (list of per-race results) and 'summary'
        (accuracy statistics).
    """
    client = bigquery.Client(project=PROJECT_ID)

    query = f"""
    WITH prediction_input AS (
        SELECT *
        FROM `{PROJECT_ID}.f1_data.v_bqml_features`
        WHERE season = {season}
    ),

    raw_predictions AS (
        SELECT *
        FROM ML.PREDICT(
            MODEL `{PROJECT_ID}.f1_data.podium_predictor`,
            TABLE prediction_input
        )
    ),

    scored AS (
        SELECT
            p.*,
            (SELECT prob.prob FROM UNNEST(p.predicted_is_podium_probs) prob
             WHERE prob.label = TRUE) AS podium_probability
        FROM raw_predictions p
    )

    SELECT
        r.name AS race_name,
        ci.name AS circuit_name,
        r.round,
        CONCAT(d.forename, ' ', d.surname) AS driver_name,
        s.grid_position,
        ROUND(s.podium_probability * 100, 1) AS predicted_podium_pct,
        s.predicted_is_podium,
        s.is_podium AS actual_podium,
        s.finish_position AS actual_finish,
        CASE
            WHEN s.predicted_is_podium = TRUE AND s.is_podium = TRUE
                THEN 'Correct Podium'
            WHEN s.predicted_is_podium = FALSE AND s.is_podium = FALSE
                THEN 'Correct Miss'
            WHEN s.predicted_is_podium = TRUE AND s.is_podium = FALSE
                THEN 'False Alarm'
            WHEN s.predicted_is_podium = FALSE AND s.is_podium = TRUE
                THEN 'Missed Podium'
        END AS prediction_outcome
    FROM scored s
    JOIN `{PROJECT_ID}.f1_data.races` r ON s.race_id = r.race_id
    JOIN `{PROJECT_ID}.f1_data.drivers` d ON s.driver_id = d.driver_id
    JOIN `{PROJECT_ID}.f1_data.circuits` ci ON r.circuit_id = ci.circuit_id
    ORDER BY r.round, s.podium_probability DESC
    """

    try:
        df = client.query(query).to_dataframe()
        predictions = df.to_dict(orient="records")

        if "prediction_outcome" in df.columns:
            summary = {
                "season": season,
                "total_predictions": len(df),
                "correct_podium": int((df["prediction_outcome"] == "Correct Podium").sum()),
                "correct_miss": int((df["prediction_outcome"] == "Correct Miss").sum()),
                "missed_podium": int((df["prediction_outcome"] == "Missed Podium").sum()),
                "false_alarm": int((df["prediction_outcome"] == "False Alarm").sum()),
            }
            total = summary["total_predictions"]
            correct = summary["correct_podium"] + summary["correct_miss"]
            summary["accuracy_pct"] = round((correct / total) * 100, 1) if total > 0 else 0
        else:
            summary = {"status": "No prediction_outcome column found"}

        return {"predictions": predictions, "summary": summary}

    except Exception as e:
        return {"error": str(e)}


# ============================================================================
# TODO 2 — Create the Visualization Agent
# ============================================================================

visualization_tool = None  # TODO 2: Create Agent, then wrap with AgentTool


# ============================================================================
# TODO 3 — Assemble the Root Agent
# ============================================================================

root_agent = None  # TODO 3: Create the root Agent
