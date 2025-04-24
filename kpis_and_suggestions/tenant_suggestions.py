#tenant_suggetsions.py
from datetime import datetime

def log(message, level="INFO", context=None):
    timestamp = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    prefix = f"[{timestamp}] [{level}]"
    # prefix = f"[{level}]"
    if context:
        prefix += f" [{context}]"
    print(f"{prefix} {message}")

# --- Simple trend detection over a list of values ---
def detect_trend(data, threshold=0.2):
    if len(data) < 3:
        return "stable"
    delta = data[-1] - data[0]
    if delta > threshold:
        return "rising"
    elif delta < -threshold:
        return "falling"
    else:
        return "stable"

# --- Main smart suggestion engine ---
def smart_suggestions(classifications, values, settings, trends=None):
    suggestions = {}

    temp = values.get("temperature")
    co2 = values.get("co2")
    humidity = values.get("humidity")
    pmv = values.get("pmv")
    t_ext = values.get("t_ext")
    hour = values.get("hour", datetime.now().hour)

    ventilation = settings["values"].get("ventilation", "nat")
    season = settings["values"].get("season", "cold")
    forecast = settings["values"].get("forecast", {})  # expects dict with keys like sun, bad_days, temp_drop
    overall_score_class = classifications.get("overall_score")

    # --- CO2 Suggestions ---
    if classifications.get("co2") in ["Y", "R"]:
        if t_ext is not None and t_ext < 5:
            suggestions["co2"] = (
                "Avoid prolonged ventilation: it's too cold outside. Open briefly or use mechanical ventilation."
                if ventilation == "nat" else
                "Increase mechanical ventilation to improve air quality."
            )
        else:
            suggestions["co2"] = (
                "Open windows to improve air quality."
                if ventilation == "nat" else
                "Increase VMC flow rate to reduce CO₂."
            )

    if classifications.get("co2") == "Y" and trends and trends.get("co2") == "rising":
        suggestions["co2_trend"] = "CO₂ is rising: consider preventive ventilation."

    if hour >= 22 and classifications.get("co2") == "R":
        suggestions["co2_night"] = "High CO₂ at night: ventilate early in the morning."

    if classifications.get("co2") == "R" and values.get("weather") == "rain":
        suggestions["co2_weather"] = "Difficult to ventilate due to rain: prefer mechanical systems."

    # --- Temperature & PMV Suggestions ---
    if classifications.get("temperature") == "Y" and pmv is not None:
        if -0.5 <= pmv < 0.5:
            suggestions["temperature"] = "Slightly outside comfort range. Adjust heating/cooling slightly."
        elif pmv < -0.5:
            suggestions["temperature"] = "Cold discomfort: raise indoor temperature."
        elif pmv > 0.5:
            suggestions["temperature"] = "Heat discomfort: lower temperature or improve airflow."

    if classifications.get("temperature") == "Y" and trends and trends.get("temperature") == "rising":
        suggestions["temp_trend_heat"] = "Temperature is rising and borderline: risk of overheating."

    if classifications.get("temperature") == "Y" and trends and trends.get("temperature") == "falling":
        suggestions["temp_trend_cold"] = "Temperature is dropping and borderline: risk of overcooling."

    if classifications.get("temperature") == "R" and pmv is not None:
        if pmv < -0.5:
            suggestions["cold_pmv"] = "Severe cold discomfort: increase heating and check insulation."
        elif pmv > 0.5:
            suggestions["hot_pmv"] = "Severe heat discomfort: ventilate or cool immediately."

    if classifications.get("temperature") == "R" and season == "warm" and forecast.get("sun"):
        suggestions["heat_sun"] = "Sunny and hot: use shading or activate cooling."

    if classifications.get("temperature") == "R" and season == "cold" and not forecast.get("sun"):
        suggestions["cold_cloudy"] = "Cold and cloudy: keep indoor temperature slightly higher."

    if classifications.get("temperature") == "R" and t_ext is not None and t_ext < 0 and ventilation == "nat":
        suggestions["extreme_cold"] = "Extreme cold outside: avoid prolonged natural ventilation."

    if classifications.get("temperature") == "Y" and pmv is not None and trends.get("temperature") == "rising":
        suggestions["pmv_heat_border"] = "Comfort zone at risk due to warming: intervene early."

    if classifications.get("temperature") == "Y" and pmv is not None and trends.get("temperature") == "falling":
        suggestions["pmv_cold_border"] = "Comfort zone at risk due to cooling: increase heating if needed."

    if forecast.get("temp_drop") and classifications.get("temperature") == "Y":
        suggestions["night_cooling"] = "Forecasted temperature drop: ventilate in the evening to cool down."

    # --- PMV and PPD Comfort ---
    if classifications.get("pmv") in ["Slightly Cold", "Slightly Warm"]:
        suggestions["comfort"] = "Thermal comfort not ideal: check clothing or airflow."

    if classifications.get("pmv") in ["Very Cold", "Very Warm"]:
        suggestions["pmv_extreme"] = "Severe thermal discomfort: act on temperature and insulation."

    if classifications.get("ppd") == "R":
        suggestions["ppd"] = "High discomfort perception: check all parameters (T, RH, airflow)."

    # --- Humidity ---
    if classifications.get("humidity") == "R":
        if humidity is not None:
            if humidity < 30:
                suggestions["humidity"] = "Air is too dry: use humidifier or add plants."
            elif humidity > 70:
                suggestions["humidity"] = "Humidity too high: dehumidify or ventilate more."

    if classifications.get("humidity") == "R" and values.get("weather") == "rain":
        suggestions["humidity_weather"] = "Rain outside: natural ventilation less effective, use VMC."

    # --- VOC & PM10 ---
    if classifications.get("voc") == "R":
        suggestions["voc"] = "High VOCs: avoid chemical sources and ventilate."

    if classifications.get("voc") == "Y" and trends and trends.get("voc") == "rising":
        suggestions["voc_trend"] = "VOCs are rising: ventilate early or remove sources."

    if classifications.get("pm10") == "R":
        suggestions["pm10"] = "High PM10: avoid opening windows, consider air purification."

    if classifications.get("pm10") == "Y" and trends and trends.get("pm10") == "rising":
        suggestions["pm10_trend"] = "PM10 is increasing: prepare to purify air."

    # --- IAQ Indicators ---
    if classifications.get("icone") == "R" or classifications.get("ieqi") == "R":
        suggestions["iaq"] = "Critical air quality: consider air purifiers or targeted ventilation."

    if (classifications.get("icone") == "R" or classifications.get("ieqi") == "R") and forecast.get("bad_days", 0) >= 2:
        suggestions["iaq_persist"] = "Persistent poor IAQ expected: consider structural solutions."

    # --- Drafts / Natural Ventilation in Cold ---
    if classifications.get("temperature") == "R" and classifications.get("humidity") == "R" and ventilation == "nat":
        suggestions["draft"] = "Cold + dry + natural ventilation: reduce drafts or humidify."

    # --- Overall Score-based combinations ---
    for metric, label in classifications.items():
        if overall_score_class == "G" and label in ["R", "Extreme"]:
            suggestions[f"score_metric_{metric}"] = f"Environment is good overall, but {metric} is critical: take action."

    if overall_score_class in ["G", "Y"] and classifications.get("voc") == "R" and forecast.get("bad_days", 0) >= 2:
        suggestions["voc_score"] = "VOC levels are high and forecast is bad: purify or ventilate now."

    if overall_score_class == "Y" and trends and all(t == "falling" for t in trends.values()):
        suggestions["score_improving"] = "Conditions are improving: maintain current settings."

    if overall_score_class == "G" and classifications.get("co2") == "R" and hour >= 22:
        suggestions["score_co2_night"] = "CO₂ is high at night despite good score: ventilate in the morning."

    if overall_score_class == "R" and all(classifications.get(k) == "G" for k in ["voc", "pm10", "humidity"]):
        suggestions["score_discomfort"] = "Environment score is bad but air is fine: check temperature or thermal comfort."

    if overall_score_class == "Y" and sum(1 for k in classifications if classifications[k] == "Y") >= 3 and any(tr == "rising" for tr in trends.values()):
        suggestions["score_borderline"] = "Several parameters are borderline and worsening: intervene before it gets worse."

    if overall_score_class == "G" and ((classifications.get("voc") == "Y" and trends.get("voc") == "rising") or (classifications.get("pm10") == "Y" and trends.get("pm10") == "rising")):
        suggestions["score_pollutants"] = "Air seems fine but pollutants are rising: act before they become critical."

    return suggestions

# --- Public wrapper ---
def get_tenant_suggestions(classifications, temp=None, humidity=None, co2=None, t_ext=None, hour=None, pmv=None, trends=None, settings=None, enabled_suggestions=None):
    values = {
        "temperature": temp,
        "humidity": humidity,
        "co2": co2,
        "pmv": pmv,
        "t_ext": t_ext,
        "hour": hour or datetime.now().hour,
        "weather": settings["values"].get("weather"),
        "forecast": settings["values"].get("forecast", {})
    }

    all_suggestions = smart_suggestions(classifications, values, settings, trends)

    if enabled_suggestions is not None:
        filtered = {k: v for k, v in all_suggestions.items() if k in enabled_suggestions}
        skipped = set(all_suggestions) - set(filtered)
        if skipped:
            log(f"Skipped disabled suggestions: {', '.join(skipped)}", level="DEBUG", context="Suggestions")
        if filtered:
            log(f"Returning {len(filtered)} tenant suggestions", context="Suggestions")
        return filtered

    log(f"Returning {len(all_suggestions)} tenant suggestions (no filtering applied)", context="Suggestions")
    return all_suggestions

