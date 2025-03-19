# Revised KPIs Calculation Module (English version)
import numpy as np

# Basic Classifications (Temperature, Humidity, CO2)
def classify_temperature(temp, season, ventilation, t_ext=None):
    if temp == -999:
        return "Unknown"

    if ventilation == "nat" and t_ext is not None:
        # Adaptive Comfort based on EN 16798-1 Annex B
        t_comf = 0.33 * t_ext + 18.8
        if abs(temp - t_comf) <= 3:
            return "G"
        elif abs(temp - t_comf) <= 4:
            return "Y"
        else:
            return "R"

    # Mechanical ventilation -> PMV-based classification
    if season == "warm":
        if 23 <= temp <= 26:
            return "G"
        elif 20 <= temp < 23 or 26 < temp <= 27:
            return "Y"
        else:
            return "R"
    elif season == "cold":
        if 20 <= temp <= 23:
            return "G"
        elif 19 <= temp < 20 or 23 < temp <= 26:
            return "Y"
        else:
            return "R"
    return "Unknown season"

def classify_humidity(humidity):
    if humidity == -999:
        return "Unknown"
    if 30 <= humidity <= 60:
        return "G"
    elif 20 <= humidity < 30 or 60 < humidity <= 70:
        return "Y"
    else:
        return "R"


def classify_co2(co2, ventilation="nat"):
    if co2 == -999:
        return "Unknown"

    if ventilation == "mech":
        if co2 <= 600:
            return "Too Good"
        elif 600 < co2 <= 1200:
            return "Good"
        elif 1200 < co2 <= 1700:
            return "Acceptable"
        elif 1700 < co2 <= 2500:
            return "Critical"
        else:
            return "Extreme"

    # Natural ventilation default thresholds
    if co2 <= 1200:
        return "G"
    elif 1200 < co2 <= 1500:
        return "Y"
    else:
        return "R"


# Adaptive Comfort (EN 16798-1) with running mean temperature
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

# Running Mean Outdoor Temperature Calculation
def running_mean_temperature(temps):
    # temps: list of last 7 daily mean outdoor temperatures [t-1, t-2, ..., t-7]
    if len(temps) == 7:
        weighted_sum = temps[0] + 0.8 * temps[1] + 0.6 * temps[2] + 0.5 * temps[3] + 0.4 * temps[4] + 0.3 * temps[5] + 0.2 * temps[6]
        return weighted_sum / 3.8
    return None

# PMV / PPD Calculation (ISO 7730) with hardcoded met and clo
def calculate_pmv(season, ta, tr, vel, rh):
    met = 1.2
    clo = 0.5 if season == "warm" else 1.0

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


# Revised ICONE without temperature and humidity
def calculate_icone(co2, pm10, tvoc):
    ref_values = {"co2": 1000, "pm10": 50, "tvoc": 0.3}
    co2_norm = co2 / ref_values["co2"]
    pm10_norm = pm10 / ref_values["pm10"]
    tvoc_norm = tvoc / ref_values["tvoc"]
    return 0.4 * co2_norm + 0.3 * pm10_norm + 0.3 * tvoc_norm


# IEQI remains temperature and humidity dependent
def calculate_ieqi(icone, temperature, humidity):
    temp_opt = 22
    hum_opt = 50
    temp_index = abs(temperature - temp_opt) / (26 - 18)
    hum_index = abs(humidity - hum_opt) / (60 - 40)
    return 0.5 * icone + 0.3 * temp_index + 0.2 * hum_index


# Advanced KPIs Classifications
def classify_pmv(pmv):
    if pmv < -2.5:
        return "Very Cold"
    elif -2.5 <= pmv < -1.5:
        return "Cold"
    elif -1.5 <= pmv < -0.5:
        return "Slightly Cold"
    elif -0.5 <= pmv <= 0.5:
        return "Neutral"
    elif 0.5 < pmv <= 1.5:
        return "Slightly Warm"
    elif 1.5 < pmv <= 2.5:
        return "Warm"
    else:
        return "Very Warm"


def classify_ppd(ppd):
    if ppd < 5:
        return "Excellent"
    elif 5 <= ppd < 10:
        return "Good"
    elif 10 <= ppd < 25:
        return "Medium"
    elif 25 <= ppd < 75:
        return "Poor"
    else:
        return "Very Poor"


def classify_ieqi(ieqi):
    if ieqi <= 1.0:
        return "Excellent"
    elif 1.0 < ieqi <= 2.0:
        return "Good"
    elif 2.0 < ieqi <= 3.0:
        return "Moderate"
    elif 3.0 < ieqi <= 4.0:
        return "Poor"
    else:
        return "Very Poor"


def classify_icone(icone):
    if icone <= 1.0:
        return "Excellent"
    elif 1.0 < icone <= 2.0:
        return "Good"
    elif 2.0 < icone <= 3.0:
        return "Moderate"
    elif 3.0 < icone <= 4.0:
        return "Poor"
    else:
        return "Very Poor"
