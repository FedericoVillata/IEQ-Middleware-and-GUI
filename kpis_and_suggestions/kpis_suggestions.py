from datetime import datetime

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
    hour = datetime.now().hour

    ventilation = settings["values"].get("ventilation", "nat")

    # --- CO2 Suggestions ---
    if classifications.get("co2") in ["Y", "R"]:
        if t_ext is not None and t_ext < 5:
            suggestions["co2"] = (
                "Evita aerazione prolungata: l'esterno è troppo freddo. Apri brevemente o usa ventilazione meccanica."
                if ventilation == "nat" else
                "Aumentare la ventilazione meccanica per migliorare la qualità dell'aria."
            )
        else:
            suggestions["co2"] = (
                "Aprire le finestre per migliorare l’aria."
                if ventilation == "nat" else
                "Aumentare portata della VMC per ridurre la CO2."
            )

    # --- Temperature & PMV-based comfort suggestions ---
    if classifications.get("temperature") == "Y" and pmv is not None:
        if -0.5 <= pmv < 0.5:
            suggestions["temperature"] = "Temperatura lievemente fuori comfort. Regolare leggermente il riscaldamento."
        elif pmv < -0.5:
            suggestions["temperature"] = "Disagio da freddo: aumentare la temperatura ambiente."
        elif pmv > 0.5:
            suggestions["temperature"] = "Disagio da caldo: ridurre temperatura o aumentare ventilazione."

    # --- PMV discomfort suggestions ---
    if classifications.get("pmv") in ["Slightly Cold", "Slightly Warm"]:
        suggestions["comfort"] = "Comfort non ottimale: rivedere abbigliamento o ventilazione."

    # --- IAQ suggestions if ICONE or IEQI are red ---
    if classifications.get("icone") == "R" or classifications.get("ieqi") == "R":
        suggestions["iaq"] = "Qualità dell'aria critica. Considerare l'uso di purificatori o areazione mirata."

    # --- Proactive suggestions based on trends ---
    if trends:
        if trends.get("co2") == "rising" and classifications.get("co2") == "Y":
            suggestions["co2_trend"] = "La CO2 sta aumentando rapidamente. Prevedere ventilazione preventiva."

        if trends.get("temperature") == "rising" and classifications.get("temperature") == "Y":
            suggestions["temp_trend"] = "La temperatura è in aumento e fuori soglia: rischio surriscaldamento."

    # --- Nighttime suggestion for CO2 ---
    if hour >= 22 and classifications.get("co2") == "R":
        suggestions["night"] = "CO2 elevata durante la notte: ventilare al mattino presto."

    return suggestions

# --- Public wrapper for backward compatibility with existing code ---
def get_suggestions(classifications, temp=None, humidity=None, co2=None, t_ext=None, hour=None, pmv=None, trends=None, settings=None):
    values = {
        "temperature": temp,
        "humidity": humidity,
        "co2": co2,
        "pmv": pmv,
        "t_ext": t_ext,
        "hour": hour or datetime.now().hour
    }
    return smart_suggestions(classifications, values, settings, trends)
