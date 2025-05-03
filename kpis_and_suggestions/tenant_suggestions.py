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
    if t_ext is None:
        log("Warning: t_ext not provided; suggestions may be less accurate", level="WARN", context="Suggestions")

    hour = values.get("hour", datetime.now().hour)

    ventilation = settings["values"].get("ventilation", "nat")
    season = settings["values"].get("season", "cold")
    forecast = settings["values"].get("forecast", {})  # expects dict with keys like sun, bad_days, temp_drop
    overall_score_class = classifications.get("overall_score")

    # --- CO2 Suggestions ---
    season = settings["values"].get("season", "cold")

    if classifications.get("co2") in ["Y", "R"]:
        if t_ext is not None and t_ext < 5:
            suggestions["co2"] = (
                "Avoid prolonged ventilation: it's too cold outside. Open briefly or use your mechanical system to improve air exchange."
            )
        elif t_ext is not None and values.get("t_int") is not None and values.get("weather") not in ["rain", "snow"]:
            t_int = values.get("t_int")
            if (season == "warm" and t_ext >= 10 and abs(t_int - t_ext) <= 7) or (season == "cold" and t_ext >= 5 and abs(t_int - t_ext) <= 5):
                suggestions["co2_norm"] = (
                    "Open windows to improve air quality, or adjust your mechanical system if available."
                )



    if classifications.get("co2") == "Y" and trends and trends.get("co2") == "rising":
        suggestions["co2_trend"] = "CO₂ is rising: consider preventive ventilation."

    if hour >= 22 and classifications.get("co2") == "R":
        suggestions["co2_night"] = "High CO₂ levels detected at night. Remember to ventilate early in the morning to refresh the air."

    if classifications.get("co2") == "R" and values.get("weather") == "rain":
        suggestions["co2_weather"] = "Difficult to ventilate due to rain: prefer mechanical systems."

    # --- Temperature & PMV Suggestions ---
    if classifications.get("temperature") == "Y":
        pmv_class = classifications.get("pmv")
        if pmv_class in ["Slightly Cold", "Slightly Warm"]:
            suggestions["temperature"] = "Comfort slightly outside the optimal range: adjust heating or cooling slightly."
        elif pmv_class in ["Cold", "Very Cold"]:
            suggestions["temperature_cold"] = "Cold discomfort detected: increase indoor temperature."
        elif pmv_class in ["Warm", "Very Warm"]:
            suggestions["temperature_hot"] = "Heat discomfort detected: lower temperature or improve airflow."


    if classifications.get("temperature") == "Y" and trends and trends.get("temperature") == "rising":
        suggestions["temp_trend_heat"] = "Temperature is borderline and rising: monitor the environment to prevent overheating."

    if classifications.get("temperature") == "Y" and trends and trends.get("temperature") == "falling":
        suggestions["temp_trend_cold"] = "Temperature is borderline and dropping: monitor to avoid excessive cooling."

    if classifications.get("temperature") == "R":
        pmv_class = classifications.get("pmv")
        if pmv_class in ["Very Cold", "Cold"]:
            suggestions["cold_pmv"] = "Severe cold discomfort: increase heating and check insulation."
        elif pmv_class in ["Warm", "Very Warm"]:
            suggestions["hot_pmv"] = "Severe heat discomfort: ventilate or cool immediately."


    if classifications.get("temperature") == "R" and season == "warm" and forecast.get("sun"):
        suggestions["heat_sun"] = "Sunny and hot: use shading or activate cooling."

    if classifications.get("temperature") == "R" and season == "cold" and not forecast.get("sun"):
        suggestions["cold_cloudy"] = "Cold and cloudy: keep indoor temperature slightly higher."

    if classifications.get("temperature") == "R" and t_ext is not None and t_ext < 0 and ventilation == "nat":
        suggestions["extreme_cold"] = "Extreme cold outside: avoid prolonged natural ventilation."

    if classifications.get("temperature") == "Y" and pmv is not None and trends.get("temperature") == "rising" and season == "warm":
        suggestions["pmv_heat_border"] = "It is starting to get warmer. Adjust the temperature early to stay comfortable."

    if classifications.get("temperature") == "Y" and pmv is not None and trends.get("temperature") == "falling" and season == "cold":
        suggestions["pmv_cold_border"] = "It is starting to get cooler. Turn up the heating if needed to stay comfortable."

    if forecast.get("temp_drop") and classifications.get("temperature") == "Y":
        suggestions["night_cooling"] = "Forecasted temperature drop: ventilate in the evening to cool down."

    # --- PMV and PPD Comfort ---
    if classifications.get("pmv") in ["Slightly Cold", "Slightly Warm"]:
        suggestions["comfort"] = "Thermal comfort not ideal: check clothing or airflow."

    if classifications.get("ppd") == "R":
        suggestions["ppd"] = "Many people might feel uncomfortable: check if temperature, humidity or ventilation need adjustments."

    # --- Humidity ---
    if classifications.get("humidity") == "R":
        if humidity is not None:
            if humidity < 50:
                suggestions["humidity"] = "The air is very dry: consider using a humidifier or adding some plants."
            elif humidity >= 50:
                suggestions["humidity_high"] = "The air is too humid: use a dehumidifier or ventilate more."


    if classifications.get("humidity") == "R" and values.get("weather") == "rain":
        suggestions["humidity_weather"] = "It is raining and the air is already humid: avoid opening windows and use mechanical ventilation or a dehumidifier."

    # --- VOC & PM10 ---
    if classifications.get("voc") == "R":
        suggestions["voc"] = "High VOC levels detected: reduce the use of chemicals and ventilate the space well."

    if classifications.get("voc") == "Y" and trends and trends.get("voc") == "rising":
        suggestions["voc_trend"] = "VOCs are rising: ventilate early or remove sources."

    if classifications.get("pm10") == "R":
        suggestions["pm10"] = "High PM10 levels: keep windows closed and use an air purifier if possible."

    if classifications.get("pm10") == "Y" and trends and trends.get("pm10") == "rising":
        suggestions["pm10_trend"] = "PM10 levels are rising: get ready to close windows or use a purifier."

    # --- IAQ Indicators ---
    if classifications.get("icone") == "R" or classifications.get("ieqi") == "R":
        suggestions["iaq"] = "Critical air quality: consider air purifiers or targeted ventilation."

    if (classifications.get("icone") == "R" or classifications.get("ieqi") == "R") and forecast.get("bad_days", 0) >= 2:
        suggestions["iaq_persist"] = "Poor air quality is expected to persist: consider long-term solutions like ventilation systems or purifiers."

    # --- Drafts / Natural Ventilation in Cold ---
    if classifications.get("temperature") == "R" and classifications.get("humidity") == "R" and ventilation == "nat":
        suggestions["draft"] = "Cold and dry air detected with natural ventilation: try reducing drafts and adding humidity."

    # --- Overall Score-based combinations ---
    for metric, label in classifications.items():
        if overall_score_class == "G" and label in ["R", "Extreme"]:
            suggestions[f"score_metric_{metric}"] = f"Overall conditions are good, but attention needed: {metric} is critical. Please act accordingly."

    if overall_score_class in ["G", "Y"] and classifications.get("voc") == "R" and forecast.get("bad_days", 0) >= 2:
        suggestions["voc_score"] = "Air pollution is high and will persist. Purify the air or ventilate well as soon as possible."

    good_trends = 0
    total_trends = 0

    for metric, trend in (trends or {}).items():
        if metric == "temperature":
            if season == "cold" and trend == "rising":
                good_trends += 1
            elif season == "warm" and trend == "falling":
                good_trends += 1
        elif metric in ["co2", "voc", "pm10", "humidity"]:
            if trend == "falling":
                good_trends += 1
        total_trends += 1

    # Consider improving if most monitored parameters are moving in the right direction
    if overall_score_class == "Y" and total_trends > 0 and good_trends / total_trends >= 0.7:
        suggestions["score_improving"] = "Conditions are improving: keep current actions or settings."


    if overall_score_class == "G" and classifications.get("co2") == "R" and hour >= 22:
        suggestions["score_co2_night"] = "CO₂ is high at night despite good score: ventilate in the morning."

    if overall_score_class == "R" and all(classifications.get(k) == "G" for k in ["voc", "pm10", "humidity"]):
        suggestions["score_discomfort"] = "Environment score is bad but air is fine: check temperature or thermal comfort."

    gyr_keys = ["temperature", "humidity", "co2", "icone", "ieqi"]  # just the ones using G/Y/R classes
    count_yellow = sum(1 for k in gyr_keys if classifications.get(k) == "Y")

    if overall_score_class == "Y" and count_yellow >= 3 and any(tr == "rising" for tr in trends.values()):
        suggestions["score_borderline"] = "Several parameters are borderline and worsening: intervene before it gets worse."


    if overall_score_class == "G" and ((classifications.get("voc") == "Y" and trends.get("voc") == "rising") or (classifications.get("pm10") == "Y" and trends.get("pm10") == "rising")):
        suggestions["score_pollutants"] = "Air seems fine, but pollutants are rising: act before they become critical."

    return suggestions

# --- Public wrapper ---
def get_tenant_suggestions(classifications, temp=None, humidity=None, co2=None, t_ext=None, hour=None, pmv=None, trends=None, settings=None, enabled_suggestions=None, name_to_id=None):
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

    final_suggestions = {}
    for name, text in all_suggestions.items():
        suggestion_id = name_to_id.get(name)
        if suggestion_id and (enabled_suggestions is None or suggestion_id in enabled_suggestions):
            final_suggestions[suggestion_id] = text


    log(f"Returning {len(final_suggestions)} tenant suggestions with IDs", context="Suggestions")
    return final_suggestions


