#kpis_classification.py
import numpy as np
from datetime import datetime
from pythermalcomfort import pmv_ppd  
from math import exp


def log(message, level="INFO", context=None):
    timestamp = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    prefix = f"[{timestamp}] [{level}]"
    # prefix = f"[{level}]"
    if context:
        prefix += f" [{context}]"
    print(f"{prefix} {message}")

# -----------------------------
# Basic Classifications
# -----------------------------

def classify_temperature(temp, season, t_ext, settings, adaptive_range=None):
    thresholds = settings["thresholds"]
    ventilation = settings["values"].get("ventilation")

    if temp == -999:
        log("Temperature is -999, cannot classify", level="WARN", context="classify_temperature")
        return "Unknown"
    

    if ventilation == "nat":
        t_comf = 0.33 * t_ext + 18.8

        if adaptive_range is None:
            log("Missing adaptive_range for natural ventilation", level="ERROR", context="classify_temperature")
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

    if isinstance(t_thresh["G"], list):
        g_min, g_max = t_thresh["G"]
        y_min, y_max = t_thresh["Y"]
        r1_min, r1_max, r2_min, r2_max = t_thresh["R"]

        if g_min <= temp <= g_max:
            return "G"
        elif y_min <= temp <= g_min or g_max <= temp <= y_max:
            return "Y"
        elif r1_min <= temp < y_min or temp > y_max:
            return "R"
        else:
            return "Unknown"
    else:
        if temp <= t_thresh["G"]:
            return "G"
        elif temp <= t_thresh["Y"]:
            return "Y"
        else:
            return "R"

def classify_humidity(humidity, settings):
    thresholds = settings["thresholds"]["humidity"]
    if humidity == -999:
        log("Humidity is -999, cannot classify", level="WARN", context="classify_humidity")
        return "Unknown"

    if isinstance(thresholds["G"], list):
        g_min, g_max = thresholds["G"]
        y_min, y_max = thresholds["Y"]
        r1_min, r1_max, r2_min, r2_max = thresholds["R"]

        if g_min <= humidity <= g_max:
            return "G"
        elif y_min <= humidity < g_min or g_max < humidity <= y_max:
            return "Y"
        elif humidity < r1_max or humidity > r2_min:
            return "R"
        else:
            return "Unknown"
    else:
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
        log("CO2 is -999, cannot classify", level="WARN", context="classify_co2")
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

# def calculate_pmv(season, ta, tr, vel, rh, settings):
#     values = settings["values"]
#     met = values.get("met", 1.2)
#     clo_key = "clo_warm" if season == "warm" else "clo_cold"
#     clo = values.get(clo_key, 1.0)

#     pa = rh * 10 * np.exp(16.6536 - 4030.183 / (ta + 235))
#     icl = 0.155 * clo
#     m = met * 58.15
#     w = 0
#     fcl = 1 + 1.29 * icl if icl < 0.078 else 1.05 + 0.645 * icl
#     t_cl = ta
#     for _ in range(5):
#         hc = max(12.1 * np.sqrt(vel), 2.38 * abs(t_cl - ta) ** 0.25)
#         t_cl = (35.7 - 0.028 * (m - w)) / (3.96e-8 * fcl * ((t_cl + 273) ** 4 - (tr + 273) ** 4) + hc * fcl)

#     hr = 3.96e-8 * fcl * ((t_cl + 273) ** 4 - (tr + 273) ** 4)
#     c = hc * fcl * (t_cl - ta)
#     e = 0.42 * (m - w - 58.15) if m > 58.15 else 0
#     res = 0.0014 * m * (34 - ta) + 0.0173 * m * (5.87 - pa)
#     l = max(-30, min(30, m - w - hr - c - e - res))
#     pmv = (0.303 * np.exp(-0.036 * m) + 0.028) * l
#     return pmv

# def calculate_ppd(pmv):
#     return 100 - 95 * np.exp(-0.03353 * (pmv ** 4) - 0.2179 * (pmv ** 2))

def calculate_pmv(season: str, ta: float, tr: float, vel: float,
                  rh: float, settings: dict) -> float:
    """PMV conforme ISO 7730 / ASHRAE 55 (usa pythermalcomfort)."""
    vals = settings["values"]
    met = vals.get("met", 1.2)
    clo = vals.get("clo_warm" if season == "warm" else "clo_cold", 0.5)

    res = pmv_ppd(
        tdb=ta, tr=tr, vr=vel, rh=rh,
        met=met, clo=clo, wme=0, standard="ISO"
    )
    pmv = res["pmv"]
    log(f"PMV input: ta={ta:.2f}, rh={rh:.2f} → pmv={pmv:.3f}", context="debug_pmv")
    return pmv


def calculate_ppd(pmv: float) -> float:
    """PPD secondo ISO 7730 (puoi anche usare res['ppd'])"""
    return 100 - 95 * exp(-0.03353 * pmv*4 - 0.2179 * pmv*2)


# -----------------------------
# IAQ Indices
# -----------------------------

def calculate_icone(co2=None, pm10=None, tvoc=None):
    ref_values = {"co2": 1000, "pm10": 50, "tvoc": 300} #tvoc in µg/m³
    components = []
    weights = []

    if co2 is not None:
        components.append(0.4 * (co2 / ref_values["co2"]))
        weights.append(0.4)
    if pm10 is not None:
        components.append(0.3 * (pm10 / ref_values["pm10"]))
        weights.append(0.3)
    if tvoc is not None:
        tvoc_ug_m3 = tvoc * 4  # Convert from ppb to µg/m³
        components.append(0.3 * (tvoc_ug_m3 / ref_values["tvoc"]))
        weights.append(0.3)


    if not components:
        return None  

    return sum(components) / sum(weights)  


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
    elif metric < thresholds["Y"]:
        return "Y"
    elif metric >= thresholds["Y"]:
        return "R"
    else:
        log(f"Metric {metric} did not match thresholds", level="WARN", context="classify_generic")
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
    log(f"PMV value {pmv} did not match any classification", level="WARN", context="classify_pmv")
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
    Calculates a weighted overall environment score (0–100),
    skipping missing or unknown classifications.
    """

    label_to_score = settings["label_to_score"]
    weights = settings["weights"]

    total_score = 0.0
    total_weight = 0.0

    for metric, label in classifications.items():
        if label is None or label == "Unknown":
            continue  # Skip missing or unknown data

        weight = weights.get(metric, 0.0)
        score = label_to_score.get(label, 0)

        normalized_score = (score / 3) * weight  # scale to weighted percentage
        total_score += normalized_score
        total_weight += weight

    if total_weight == 0:
        return 0  # No valid data, fallback to score 0

    normalized_total = total_score / total_weight * 100  # Rescale to 0-100

    return round(normalized_total)

def overall_score_continuous(kpi_values, settings):
    """
    Compute a continuous (0–100) overall score, using thresholds and weights per metric.
    Requires: kpi_values = {"temperature": 22.3, "humidity": 40.1, ..., etc.}
    settings must contain: weights + thresholds dict with G/Y/R ranges per metric.
    """

    weights = settings["weights"]
    thresholds = settings["thresholds"]

    total_score = 0.0
    total_weight = 0.0

    for metric, value in kpi_values.items():
        if value is None or metric not in weights or metric not in thresholds:
            continue

        weight = weights[metric]
        thr = thresholds[metric]

        if metric == "pmv":
            min_pmv = thr["Very Cold"]
            max_pmv = thr["Very Warm"]
            neutral_center = thr["Neutral"]

            if min_pmv <= value <= neutral_center:
                score = (value - min_pmv) / (neutral_center - min_pmv)
            elif neutral_center < value <= max_pmv:
                score = (max_pmv - value) / (max_pmv - neutral_center)
            else:
                score = 0.0

            score = max(0.0, min(1.0, score))

        # symmetric classification (with 2 "yellow" sides)
        elif isinstance(thr.get("G"), list) and isinstance(thr.get("Y"), list) and isinstance(thr.get("R"), list):
            g_min, g_max = thr["G"]
            y1_min, y1_max = thr["Y"]
            r1_min, r1_max, r2_min, r2_max = thr["R"]

            if g_min <= value <= g_max:
                score = 1.0
            elif y1_min <= value < g_min:
                score = (value - y1_min) / (g_min - y1_min) * 0.7
            elif g_max < value <= y1_max:
                score = (y1_max - value) / (y1_max - g_max) * 0.7
            elif r1_min <= value < y1_min:
                score = (value - r1_min) / (y1_min - r1_min) * 0.3
            elif y1_max < value <= r2_max:
                score = (r2_max - value) / (r2_max - y1_max) * 0.3
            else:
                score = 0.0

        # monotonic classification (co2, ieqi, icone, etc.)
        elif isinstance(thr.get("G"), (int, float)):
            g = thr["G"]
            y = thr["Y"]
            r = thr["R"]

            if value <= g:
                score = 1.0
            elif value <= y:
                score = (y - value) / (y - g) * 0.7
            elif value <= r:
                score = (r - value) / (r - y) * 0.3
            else:
                score = 0.0
        else:
            score = 0.0  # fallback

        total_score += score * weight
        total_weight += weight

    if total_weight == 0:
        return 0

    return round((total_score / total_weight) * 100)        


def classify_overall_score(score, settings):
    thresholds = settings["thresholds"]["overall_score_classification"]

    if 0 <= score <= thresholds["G"]:
        if score > thresholds["Y"]:
            return "G"
        elif score > thresholds["R"]:
            return "Y"
        else:
            return "R"
    else:
        return "Unknown"

