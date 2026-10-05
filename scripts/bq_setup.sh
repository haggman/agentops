#!/usr/bin/env bash
# BigQuery for the demo: dataset, 100,000-row table, logistic-regression model, prediction function.
# Safe to rerun: each piece is checked first.  bash ~/agentops/scripts/bq_setup.sh
set -euo pipefail
# shellcheck disable=SC1091
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"
DS="${PROJECT_ID}:${BQ_DATASET}"

if bq --project_id="$PROJECT_ID" show --dataset "$DS" >/dev/null 2>&1; then
  ok "dataset ${BQ_DATASET}"
else
  bq --project_id="$PROJECT_ID" --location="$BQ_LOCATION" mk --dataset \
     --description "AgentOps demo: diabetes prediction with BigQuery ML + ADK" "$DS" >/dev/null
  made "dataset ${BQ_DATASET}"
fi

ROWS="$(bq --project_id="$PROJECT_ID" query --use_legacy_sql=false --format=csv \
        "SELECT COUNT(*) FROM \`${PROJECT_ID}.${BQ_DATASET}.diabetes_raw\`" 2>/dev/null | tail -1 || true)"
if [ "$ROWS" = "100000" ]; then
  ok "table diabetes_raw (100,000 rows)"
else
  retry bq --project_id="$PROJECT_ID" --location="$BQ_LOCATION" load --autodetect --skip_leading_rows=1 \
     --source_format=CSV --replace "${BQ_DATASET}.diabetes_raw" "$GCS_URI" >/dev/null
  made "table diabetes_raw loaded from $GCS_URI"
fi

if bq --project_id="$PROJECT_ID" show --model "${DS}.diabetes_model" >/dev/null 2>&1; then
  ok "model diabetes_model"
else
  echo "   … training diabetes_model (1-3 minutes)"
  bq --project_id="$PROJECT_ID" query --use_legacy_sql=false --quiet "
CREATE OR REPLACE MODEL \`${BQ_DATASET}.diabetes_model\`
OPTIONS (model_type='LOGISTIC_REG', input_label_cols=['diabetes'], auto_class_weights=TRUE,
         data_split_method='AUTO_SPLIT', max_iterations=20)
AS SELECT * FROM \`${BQ_DATASET}.diabetes_raw\`" >/dev/null
  made "model diabetes_model"
fi

if bq --project_id="$PROJECT_ID" show --routine "${DS}.predict_diabetes" >/dev/null 2>&1; then
  ok "table function predict_diabetes"
else
  # Missing inputs fall back to population averages from the study data.
  bq --project_id="$PROJECT_ID" query --use_legacy_sql=false --quiet "$(sed "s/__DATASET__/${BQ_DATASET}/g" <<'SQL'
CREATE OR REPLACE TABLE FUNCTION `__DATASET__.predict_diabetes`(
  gender STRING, age FLOAT64, hypertension INT64, heart_disease INT64,
  smoking_history STRING, bmi FLOAT64, HbA1c_level FLOAT64, blood_glucose_level INT64)
AS (
  WITH input AS (
    SELECT
      COALESCE(gender, 'Female') AS gender,
      COALESCE(age, CASE WHEN COALESCE(gender, 'Female') = 'Male' THEN 41.08 ELSE 42.46 END) AS age,
      COALESCE(hypertension, 0) AS hypertension,
      COALESCE(heart_disease, 0) AS heart_disease,
      COALESCE(smoking_history, 'never') AS smoking_history,
      COALESCE(bmi, CASE WHEN COALESCE(gender, 'Female') = 'Male' THEN 27.14 ELSE 27.45 END) AS bmi,
      COALESCE(HbA1c_level, CASE WHEN COALESCE(gender, 'Female') = 'Male' THEN 5.55 ELSE 5.51 END) AS HbA1c_level,
      COALESCE(blood_glucose_level, CASE WHEN COALESCE(gender, 'Female') = 'Male' THEN 139 ELSE 137 END) AS blood_glucose_level
  )
  SELECT
    gender, ROUND(age, 2) AS age, hypertension, heart_disease, smoking_history,
    ROUND(bmi, 1) AS bmi, ROUND(HbA1c_level, 1) AS hba1c, blood_glucose_level AS blood_glucose,
    CAST(predicted_diabetes AS INT64) AS prediction,
    ROUND((SELECT prob FROM UNNEST(predicted_diabetes_probs) WHERE CAST(label AS INT64) = 1 LIMIT 1), 4) AS probability_of_diabetes,
    CASE
      WHEN (SELECT prob FROM UNNEST(predicted_diabetes_probs) WHERE CAST(label AS INT64) = 1 LIMIT 1) < 0.30 THEN 'Low Risk'
      WHEN (SELECT prob FROM UNNEST(predicted_diabetes_probs) WHERE CAST(label AS INT64) = 1 LIMIT 1) < 0.70 THEN 'Moderate Risk'
      ELSE 'High Risk'
    END AS risk_category
  FROM ML.PREDICT(MODEL `__DATASET__.diabetes_model`, TABLE input)
)
SQL
)" >/dev/null
  made "table function predict_diabetes"
fi
