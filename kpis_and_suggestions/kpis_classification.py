import numpy as np

# -----------------------------
# Basic Classifications
# -----------------------------

def classify_temperature(temp, season, t_ext, settings, adaptive_range=None):
    thresholds = settings["thresholds"]
    ventilation = settings["values"].get("ventilation")

    if temp == -999:
        return "Unknown"

    if ventilation == "nat":
        t_comf = 0.33 * t_ext + 18.8

        if adaptive_range is None:
            raise ValueError("adaptive_range must be provided for natural ventilation classification")

        cat_min, cat_max = adaptive_range
        cat3_min = t_comf - 5
        cat3_max = t_comf + 4

        if cat_min <= temp <= cat_max:
            return "G"
        elif cat3_min <= temp <= cat3_max:
            return "Y"
        else:
            return "R"

    # Mechanical ventilation thresholds
    key = f"mechanical_temp_{season}"
    t_thresh = thresholds.get(key)

    if temp <= t_thresh["G"]:
        return "G"
    elif temp <= t_thresh["Y"]:
        return "Y"
    else:
        return "R"

def classify_humidity(humidity, settings):
    thresholds = settings["thresholds"]["humidity"]
    if humidity == -999:
        return "Unknown"
    if humidity <= thresholds["G"]:
        return "G"
    elif humidity <= thresholds["Y"]:
        return "Y"
    else:
        return "R"

def classify_co2(co2, settings):
    thresholds = settings["thresholds"]
    ventilation = settings["values"].get("ventilation")

    if co2 == -999:
        return "Unknown"

    key = f"co2_{'mechanical' if ventilation == 'mech' else 'natural'}"
    co2_thresh = thresholds[key]

    if ventilation == "mech":
        if co2 <= co2_thresh["Too Good"]:
            return "Too Good"
        elif co2 <= co2_thresh["G"]:
            return "G"
        elif co2 <= co2_thresh["Y"]:
            return "Y"
        elif co2 <= co2_thresh["R"]:
            return "R"
        else:
            return "Extreme"
    else:
        if co2 <= co2_thresh["G"]:
            return "G"
        elif co2 <= co2_thresh["Y"]:
            return "Y"
        else:
            return "R"

# -----------------------------
# Adaptive Thermal Comfort
# -----------------------------

def adaptive_thermal_comfort(temps):
    t_rm = running_mean_temperature(temps)
    if t_rm is None:
        return None
    t_comf = 0.33 * t_rm + 18.8
    return {
        "Running Mean Temperature": t_rm,
        "Comfort Temperature": t_comf,
        "Acceptable Range": {
            "Cat I": (t_comf - 3, t_comf + 2),
            "Cat II": (t_comf - 4, t_comf + 3),
            "Cat III": (t_comf - 5, t_comf + 4)
        }
    }

def running_mean_temperature(temps):
    if len(temps) == 7:
        weights = [1, 0.8, 0.6, 0.5, 0.4, 0.3, 0.2]
        weighted_sum = sum(w * t for w, t in zip(weights, temps))
        return weighted_sum / 3.8
    return None

# -----------------------------
# PMV and PPD Calculations
# -----------------------------

def calculate_pmv(season, ta, tr, vel, rh, settings):
    values = settings["values"]
    met = values.get("met", 1.2)
    clo_key = "clo_warm" if season == "warm" else "clo_cold"
    clo = values.get(clo_key, 1.0)

    pa = rh * 10 * np.exp(16.6536 - 4030.183 / (ta + 235))
    icl = 0.155 * clo
    m = met * 58.15
    w = 0
    fcl = 1 + 1.29 * icl if icl < 0.078 else 1.05 + 0.645 * icl
    t_cl = ta
    for _ in range(5):
        hc = max(12.1 * np.sqrt(vel), 2.38 * abs(t_cl - ta) ** 0.25)
        t_cl = (35.7 - 0.028 * (m - w)) / (3.96e-8 * fcl * ((t_cl + 273) ** 4 - (tr + 273) ** 4) + hc * fcl)

    hr = 3.96e-8 * fcl * ((t_cl + 273) ** 4 - (tr + 273) ** 4)
    c = hc * fcl * (t_cl - ta)
    e = 0.42 * (m - w - 58.15) if m > 58.15 else 0
    res = 0.0014 * m * (34 - ta) + 0.0173 * m * (5.87 - pa)
    l = max(-30, min(30, m - w - hr - c - e - res))
    pmv = (0.303 * np.exp(-0.036 * m) + 0.028) * l
    return pmv

def calculate_ppd(pmv):
    return 100 - 95 * np.exp(-0.03353 * (pmv ** 4) - 0.2179 * (pmv ** 2))

# -----------------------------
# IAQ Indices
# -----------------------------

def calculate_icone(co2, pm10, tvoc):
    ref_values = {"co2": 1000, "pm10": 50, "tvoc": 0.3}
    co2_norm = co2 / ref_values["co2"]
    pm10_norm = pm10 / ref_values["pm10"]
    tvoc_norm = tvoc / ref_values["tvoc"]
    return 0.4 * co2_norm + 0.3 * pm10_norm + 0.3 * tvoc_norm

def calculate_ieqi(icone, temperature, humidity, settings):
    temp_opt = settings["values"].get("temp_opt", 22)
    hum_opt = settings["values"].get("hum_opt", 50)

    temp_index = abs(temperature - temp_opt) / (26 - 18)
    hum_index = abs(humidity - hum_opt) / (60 - 40)
    return 0.5 * icone + 0.3 * temp_index + 0.2 * hum_index

# -----------------------------
# Classification Functions
# -----------------------------

def classify_generic(metric, thresholds):
    if metric <= thresholds["G"]:
        return "G"
    elif metric <= thresholds["Y"]:
        return "Y"
    elif metric <= thresholds["R"]:
        return "R"
    elif "Extreme" in thresholds:
        return "Extreme"
    else:
        return "Unknown"

def classify_pmv(pmv, settings):
    thresholds = settings["thresholds"]["pmv_classification"]
    for label, bound in thresholds.items():
        if label == "Very Cold" and pmv < bound:
            return label
        elif label == "Very Warm" and pmv > thresholds["Warm"]:
            return label
        elif thresholds.get("Very Cold", -10) <= pmv <= thresholds.get("Very Warm", 10):
            if label == "Cold" and thresholds["Very Cold"] <= pmv < bound:
                return label
            elif label == "Slightly Cold" and thresholds["Cold"] <= pmv < bound:
                return label
            elif label == "Neutral" and thresholds["Slightly Cold"] <= pmv <= bound:
                return label
            elif label == "Slightly Warm" and thresholds["Neutral"] < pmv <= bound:
                return label
            elif label == "Warm" and thresholds["Slightly Warm"] < pmv <= bound:
                return label
    return "Unknown"

def classify_ppd(ppd, settings):
    thresholds = settings["thresholds"]["ppd_classification"]
    return classify_generic(ppd, thresholds)

def classify_ieqi(ieqi, settings):
    thresholds = settings["thresholds"]["ieqi_classification"]
    return classify_generic(ieqi, thresholds)

def classify_icone(icone, settings):
    thresholds = settings["thresholds"]["icone_classification"]
    return classify_generic(icone, thresholds)

# -----------------------------
# Overall Score and Classification
# -----------------------------

def overall_score(classifications, settings):
    """
    Calculates the weighted overall environment score as a whole number percentage (0 to 100).
    """

    label_to_score = settings["label_to_score"]
    weights = settings["weights"]

    total_score = 0.0

    for metric, label in classifications.items():
        weight = weights.get(metric, 0.0)
        score = label_to_score.get(label, 0)
        normalized_score = (score / 3) * weight  # scale to weighted percentage
        total_score += normalized_score

    return round(total_score)

def classify_overall_score(score, settings):
    thresholds = settings["thresholds"]["overall_score_classification"]

    if score >= thresholds["G"]:
        return "G"
    elif score >= thresholds["Y"]:
        return "Y"
    elif score >= thresholds["R"]:
        return "R"
    else:
        return "Unknown"


