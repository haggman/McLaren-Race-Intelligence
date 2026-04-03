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
# TODO 1 — Connect to BigQuery using ADK's Built-in BigQueryToolset
# ============================================================================
#
# WHAT YOU'RE BUILDING:
#   ADK ships with a first-party BigQueryToolset that gives your agent the
#   ability to discover datasets, inspect table schemas, and execute SQL —
#   all through Application Default Credentials (ADC), which are already
#   configured in your Cloud Shell environment.
#
# WHAT TO DO:
#   1. Import BigQueryCredentialsConfig and BigQueryToolset from
#      google.adk.tools.bigquery
#   2. Load ADC credentials using google.auth.default()
#   3. Create a BigQueryCredentialsConfig with those credentials
#   4. Create a BigQueryToolset instance with that config
#
# WHEN YOU'RE DONE, the toolset will provide these tools to the agent:
#   - list_dataset_ids: discover available datasets
#   - list_table_ids:   list tables in a dataset
#   - get_table_info:   inspect a table's schema
#   - execute_sql:      run SQL queries against BigQuery
#
# HINT: The import path is google.adk.tools.bigquery and the setup is
#       about 4 lines of code. ADC handles all authentication automatically.
#
# Replace the line below with your implementation:
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
#
# WHAT YOU'RE BUILDING:
#   A visualization agent that generates charts using Python code execution.
#   The agent's instructions and description are already defined in
#   prompts.py — your job is to create the agent and wrap it properly.
#
# WHAT TO DO:
#   1. Create an Agent instance with:
#      - name: "visualization_agent"
#      - model: "gemini-2.5-flash"
#      - description: VISUALIZATION_AGENT_DESCRIPTION (from prompts.py)
#      - instruction: VISUALIZATION_INSTRUCTIONS (from prompts.py)
#      - code_executor: BuiltInCodeExecutor()
#   2. Wrap it with AgentTool so the root agent can call it as a tool
#
# WHY AgentTool?
#   BuiltInCodeExecutor (which enables Python code generation and execution)
#   cannot coexist with other tool types in the same Gemini API call. By
#   wrapping the visualization agent with AgentTool, the root agent treats
#   it as a regular function call, and the viz agent runs in its own
#   isolated API call with only the code executor. No tool conflicts.
#
#   This is a real pattern you'll use whenever you need to combine agents
#   that have incompatible tool types — it's not specific to this lab.
#
# HINT: Both imports are already at the top of this file:
#       - BuiltInCodeExecutor from google.adk.code_executors
#       - AgentTool from google.adk.tools.agent_tool
#
# Replace the lines below with your implementation:
visualization_tool = None  # TODO 2: Create Agent, then wrap with AgentTool


# ============================================================================
# TODO 3 — Assemble the Root Agent
# ============================================================================
#
# WHAT YOU'RE BUILDING:
#   The root agent that ties everything together. This is where the
#   architecture becomes real — you take all the components you've built
#   and configured, and assemble them into a working agent.
#
# WHAT TO DO:
#   Create an Agent instance with:
#   1. name: "mclaren_race_intelligence"
#   2. model: "gemini-2.5-flash"
#   3. description: ROOT_AGENT_DESCRIPTION (from prompts.py)
#   4. instruction: call get_root_agent_instructions(PROJECT_ID) — this
#      returns the system prompt with your project ID embedded for
#      fully-qualified BigQuery table references
#   5. tools: a list containing ALL THREE tools the agent needs:
#      - bigquery_toolset (from TODO 1) — data access
#      - get_podium_predictions — ML inference (the function defined above)
#      - visualization_tool (from TODO 2) — chart generation
#
# WHY THIS MATTERS:
#   This is the moment where you see how an ADK agent is assembled from
#   discrete components. The model provides reasoning. The instructions
#   provide domain context. The tools provide capabilities. The agent
#   decides which tool to call based on the user's question — that
#   decision-making is what makes it an agent, not just a chatbot.
#
# HINT: Look at the imports from prompts.py at the top of this file.
#
# Replace the line below with your implementation:
root_agent = None  # TODO 3: Create the root Agent