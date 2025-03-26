# Esempio di aggiornamento del file kpis_classification.py per supportare thresholds dinamiche e parametri MET/CLO

import numpy as np

def classify_temperature(temp, season, ventilation, thresholds, t_ext=None):
    if temp == -999:
        return "Unknown"

    if ventilation == "nat" and t_ext is not None:
        t_comf = 0.33 * t_ext + 18.8
        delta_g = thresholds['adaptive_temp']['green']
        delta_y = thresholds['adaptive_temp']['yellow']
        if abs(temp - t_comf) <= delta_g:
            return "G"
        elif abs(temp - t_comf) <= delta_y:
            return "Y"
        else:
            return "R"

    warm_g = thresholds['mechanical_temp']['warm_green']
    cold_g = thresholds['mechanical_temp']['cold_green']

    if season == "warm":
        if warm_g[0] <= temp <= warm_g[1]:
            return "G"
        elif temp < warm_g[0] or temp > warm_g[1]:
            return "R"
        else:
            return "Y"
    elif season == "cold":
        if cold_g[0] <= temp <= cold_g[1]:
            return "G"
        elif temp < cold_g[0] or temp > cold_g[1]:
            return "R"
        else:
            return "Y"
    return "Unknown"


def classify_humidity(humidity, thresholds):
    if humidity == -999:
        return "Unknown"
    if thresholds['humidity']['green'][0] <= humidity <= thresholds['humidity']['green'][1]:
        return "G"
    elif thresholds['humidity']['yellow'][0] <= humidity <= thresholds['humidity']['yellow'][1]:
        return "Y"
    else:
        return "R"


def classify_co2(co2, ventilation, thresholds):
    if co2 == -999:
        return "Unknown"

    co2_limits = thresholds['co2']['mechanical'] if ventilation == "mech" else thresholds['co2']['natural']

    for level, limit in co2_limits.items():
        if co2 <= limit:
            return level
    return "Extreme"


def calculate_pmv(season, ta, tr, vel, rh, met, clo):
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


def compute_environment_score(classes, thresholds):
    scores = thresholds['environment_score']
    total_score = sum(scores.get(cls, 50) for cls in classes)
    return total_score / len(classes)


def classify_environment_score(score, thresholds):
    for label, value in thresholds['env_classification'].items():
        if score >= value:
            return label
    return "Critical"
