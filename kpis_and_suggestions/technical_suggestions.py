#technical_suggestions.py
from datetime import datetime

def log(message, level="INFO", context=None):
    timestamp = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    prefix = f"[{timestamp}] [{level}]"
    # prefix = f"[{level}]"
    if context:
        prefix += f" [{context}]"
    print(f"{prefix} {message}")

def get_technical_suggestions(classifications, feedback, metrics, settings):
    suggestions = {}

    # Extract feedback lists (default empty)
    temp_fb = feedback.get("temperature_perception", [])
    hum_fb = feedback.get("humidity_perception", [])
    env_fb = feedback.get("enviromental_satisfaction", [])

    # Get last known feedback value for each category (if any)
    def last_feedback(feedback_list):
        if not feedback_list:
            return None
        return int(feedback_list[-1]["type"])

    temp_perc = last_feedback(temp_fb)
    hum_perc = last_feedback(hum_fb)
    env_perc = last_feedback(env_fb)

    temp_class = classifications.get("temperature")
    hum_class = classifications.get("humidity")
    score_class = classifications.get("overall_score")
    pmv_class = classifications.get("pmv")

    season = settings["values"].get("season", "cold")
    t_int = metrics.get("temperature")
    t_ext = metrics.get("t_ext") or t_int

    # --- TEMPERATURE SUGGESTIONS ---
    if temp_class == "R":
        if season == "cold" or t_int < t_ext:
            if temp_perc == 3:
                suggestions["TEMP_COLD_NEUTRAL"] = (
                    "Temperature classified as critical (R – cold), but user perception = Neutral. "
                    "Suggestion: the lower thresholds might be too restrictive."
                )
        elif season == "warm" or t_int > t_ext:
            if temp_perc == 3:
                suggestions["TEMP_HOT_NEUTRAL"] = (
                    "Temperature classified as critical (R – hot), but user perception = Neutral. "
                    "Suggestion: the upper thresholds might be too tight."
                )

    if temp_class == "Y":
        if temp_perc in [4, 5]:
            suggestions["TEMP_COLD_WARM_PERCEPTION"] = (
                "Temperature classified as cold, but user perception = Warm or Very Warm. "
                "Suggestion: possible inconsistency between real comfort and classification. Check sensors and thresholds."
            )
        elif temp_perc in [1, 2]:
            suggestions["TEMP_HOT_COLD_PERCEPTION"] = (
                "Temperature classified as hot, but user perception = Cold or Very Cold. "
                "Suggestion: possible reversal in threshold logic or sensor measurement issues."
            )

    if temp_class == "G" and temp_perc in [1, 2, 4, 5]:
        suggestions["TEMP_GOOD_DISCOMFORT"] = (
            "Temperature classified as good (G), but user perception = discomfort (1, 2, 4 or 5). "
            "Suggestion: the comfort zone might not reflect actual user experience."
        )

    # --- HUMIDITY SUGGESTIONS ---
    if hum_class == "R" and hum_perc == 3:
        suggestions["HUMIDITY_CRITICAL_NEUTRAL"] = (
            "Humidity classified as critical (R), but user perception = Neutral. "
            "Suggestion: thresholds may be too strict. Consider relaxing them."
        )

    if hum_class == "Y":
        if hum_perc in [4, 5]:
            suggestions["HUMIDITY_DRY_HUMID_PERCEPTION"] = (
                "Humidity classified as too dry, but user perception = Humid or Very Humid. "
                "Suggestion: review threshold logic; possible discrepancy in measurement."
            )
        elif hum_perc in [1, 2]:
            suggestions["HUMIDITY_HUMID_DRY_PERCEPTION"] = (
                "Humidity classified as too humid, but user perception = Very Dry or Dry. "
                "Suggestion: measured humidity does not match perceived dryness. Review sensor accuracy and thresholds."
            )

    if hum_class == "G" and hum_perc in [1, 5]:
        suggestions["HUMIDITY_GOOD_EXTREME_PERCEPTION"] = (
            "Humidity classified as good (G), but user perception = Very Dry or Very Humid. "
            "Suggestion: \"G\" range may not reflect actual comfort. Consider readjusting thresholds."
        )

    # --- ENVIRONMENTAL SCORE ---
    if score_class == "G" and env_perc in [1, 2]:
        suggestions["ENV_SCORE_GOOD_UNSATISFIED"] = (
            "Overall environmental score = good (G), but satisfaction feedback = Very Unsatisfied or Unsatisfied. "
            "Suggestion: review global thresholds or consider environmental variables not currently measured."
        )
    if score_class == "R" and env_perc in [4, 5]:
        suggestions["ENV_SCORE_CRITICAL_SATISFIED"] = (
            "Overall score = critical (R), but satisfaction feedback = Very Satisfied or Satisfied. "
            "Suggestion: the system might be classifying as critical conditions perceived as acceptable."
        )

    # --- PMV CLASS SUGGESTIONS ---
    if pmv_class == "Neutral" and temp_perc in [1, 2, 4, 5]:
        suggestions["PMV_NEUTRAL_DISCOMFORT"] = (
            "PMV classified as Neutral, but user perception = Cold, Very Cold, Warm or Very Warm. "
            "Suggestion: estimated comfort not aligned with perception. Verify user profiles and met/clo parameters."
        )

    if pmv_class in ["Cold", "Very Cold"] and temp_perc in [4, 5]:
        suggestions["PMV_COLD_WARM_PERCEPTION"] = (
            "PMV = Cold or Very Cold, but perception = Warm or Very Warm. "
            "Suggestion: possible modeling or measurement error. Check consistency."
        )

    if pmv_class == "Very Warm" and temp_perc in [1, 2]:
        suggestions["PMV_VERY_WARM_COLD_PERCEPTION"] = (
            "PMV = Very Warm, but perception = Cold or Very Cold. "
            "Suggestion: thermal comfort perceived is the opposite of calculated. Verify input parameters."
        )
        
    # DEBUG: test suggestion, always triggered. Comment out if not needed.
    suggestions["_DEBUG_TEST_ALWAYS_TRIGGERED"] = (
        "Debug: this is a fake suggestion always included. Useful for testing suggestion generation and display pipelines."
    )

    log(f"Generated {len(suggestions)} technical suggestions", context="Technical")
    return suggestions

