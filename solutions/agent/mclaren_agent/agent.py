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

from .prompts import (
    ROOT_AGENT_DESCRIPTION,
    get_root_agent_instructions,
    VISUALIZATION_AGENT_DESCRIPTION,
    VISUALIZATION_INSTRUCTIONS,
)

# ============================================================================
# Configuration
# ============================================================================
PROJECT_ID = os.environ.get("GOOGLE_CLOUD_PROJECT")
LOCATION = os.environ.get("GOOGLE_CLOUD_LOCATION", "us-central1")


# ============================================================================
# TODO 1 — SOLUTION: Connect to BigQuery
# ============================================================================

credentials, _ = google.auth.default()
credentials_config = BigQueryCredentialsConfig(credentials=credentials)
bigquery_toolset = BigQueryToolset(credentials_config=credentials_config)


# ============================================================================
# BQML Podium Prediction Tool (pre-built)
# ============================================================================
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
# TODO 2 — SOLUTION: Visualization Agent + AgentTool
# ============================================================================

visualization_agent = Agent(
    name="visualization_agent",
    model="gemini-2.5-flash",
    description=VISUALIZATION_AGENT_DESCRIPTION,
    instruction=VISUALIZATION_INSTRUCTIONS,
    code_executor=BuiltInCodeExecutor(),
)

visualization_tool = AgentTool(agent=visualization_agent)


# ============================================================================
# TODO 3 — SOLUTION: Root Agent
# ============================================================================

root_agent = Agent(
    name="mclaren_race_intelligence",
    model="gemini-2.5-flash",
    description=ROOT_AGENT_DESCRIPTION,
    instruction=get_root_agent_instructions(PROJECT_ID),
    tools=[bigquery_toolset, get_podium_predictions, visualization_tool],
)