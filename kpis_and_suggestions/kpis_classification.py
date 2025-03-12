import numpy as np

# BASIC CLASSIFICATION (G ---> Green, Y ---> Yellow, R ---> Red)
def classify_temperature(temp, season):
    if temp == -999:  # Handling missing values
        return "Unknown"

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
    else:
        return "Unknown season"

def classify_humidity(humidity):
    if humidity == -999:  # Handling missing values
        return "Unknown"
    
    if 30 <= humidity <= 60:
        return "G"
    elif 20 <= humidity < 30 or 60 < humidity <= 70:
        return "Y"
    else:
        return "R"

def classify_co2(co2):
    if co2 == -999:  # Handling missing values
        return "Unknown"
    
    if co2 <= 1200:
        return "G"
    elif 1200 < co2 <= 1500:
        return "Y"
    else:
        return "R"

# ADVANCED KPIs CALCULATION

def adaptive_thermal_comfort(t_ext):
    """
    Calculates the adaptive thermal comfort range.
    t_ext: Mean outdoor temperature (°C) over the last 7 day
    """
    # Compute the comfort temperature
    t_c = 0.31 * t_ext + 17.8

    # Compute the acceptable ranges
    acceptable_range_80 = (t_c - 3.5, t_c + 3.5)
    acceptable_range_90 = (t_c - 2.5, t_c + 2.5)

    return {
        "Comfort Temperature": t_c,
        "Acceptable Range (80%)": acceptable_range_80,
        "Acceptable Range (90%)": acceptable_range_90
    }


def calculate_pmv(met, clo, ta, tr, vel, rh):
    """
    Calculates the PMV (Predicted Mean Vote) based on ISO 7730.
    met: Metabolic rate (met)
    clo: Clothing insulation (clo)
    ta: Air temperature (°C)
    tr: Mean radiant temperature (°C)
    vel: Air velocity (m/s)
    rh: Relative humidity (%)
    """
    # Constants
    pa = rh * 10 * np.exp(16.6536 - 4030.183 / (ta + 235))  # Water vapor pressure (Pa)
    icl = 0.155 * clo  # Clothing insulation (m²K/W)
    m = met * 58.15  # Metabolic rate (W/m²)
    w = 0  # Mechanical work (assumed zero)

    # Clothing factor
    if icl < 0.078:
        fcl = 1 + 1.29 * icl
    else:
        fcl = 1.05 + 0.645 * icl

    # Convective heat transfer coefficient (hc) - iterative approach
    t_cl = ta  # Initial clothing surface temperature guess
    for _ in range(5):  # Iterate 5 times to refine hc
        hc = max(12.1 * np.sqrt(vel), 2.38 * (t_cl - ta) ** 0.25)  # Iterative hc adjustment
        t_cl = tr + (ta - tr) / (1 + hc / (fcl * 3.96 * 10 ** -8 * ((ta + 273) ** 4 - (tr + 273) ** 4)))

    # Radiative heat transfer
    hr = 3.96 * 10 ** -8 * fcl * ((t_cl + 273) ** 4 - (tr + 273) ** 4)

    # Convective heat loss
    c = hc * fcl * (t_cl - ta)

    # Evaporative and respiratory heat loss
    e = 0.42 * (m - w - 58.15) if m > 58.15 else 0
    res = 0.0014 * m * (34 - ta) + 0.0173 * m * (5.87 - pa)

    # **Thermal load correction**
    l = m - w - hr - c - e - res
    l = max(-30, min(30, l))  # **Restrict values within realistic human comfort range**

    # PMV formula
    pmv = (0.303 * np.exp(-0.036 * m) + 0.028) * l

    return pmv



def calculate_ppd(pmv):
    """
    Calculates the PPD (Percentage of Dissatisfied People) based on PMV.
    """
    pdd = 100 - 95 * np.exp(-0.03353 * (pmv ** 4) - 0.2179 * (pmv ** 2))
    return pdd

def calculate_icone(co2, pm10, tvoc, temperature, humidity):
    """
    Calculate the ICONE (Indoor Air Quality Index).
    """
    # Reference values for normalization
    ref_values = {
        "co2": 1000,   # ppm
        "pm10": 50,    # µg/m³
        "tvoc": 0.3,   # mg/m³
        "temperature": (18, 26),  # Optimal comfort range (min, max) °C
        "humidity": (40, 60)  # Optimal range (%)
    }
    
    # Normalize air quality parameters
    co2_norm = co2 / ref_values["co2"]
    pm10_norm = pm10 / ref_values["pm10"]
    tvoc_norm = tvoc / ref_values["tvoc"]
    
    # Normalize temperature deviation
    temp_opt_min, temp_opt_max = ref_values["temperature"]
    temp_norm = abs(temperature - (temp_opt_min + temp_opt_max) / 2) / (temp_opt_max - temp_opt_min)
    
    # Normalize humidity deviation
    hum_opt_min, hum_opt_max = ref_values["humidity"]
    hum_norm = abs(humidity - (hum_opt_min + hum_opt_max) / 2) / (hum_opt_max - hum_opt_min)
    
    # Compute ICONE as a weighted sum
    icone = (0.3 * co2_norm + 0.3 * pm10_norm + 0.2 * tvoc_norm + 0.1 * temp_norm + 0.1 * hum_norm)
    
    return icone


def calculate_ieqi(icone, temperature, humidity):
    """
    Calculate the IEQI (Indoor Environmental Quality Index) considering ICONE, temperature, and humidity.
    """
    # Reference values for temperature and humidity
    temp_opt = 22  # Optimal indoor temperature in °C
    temp_max, temp_min = 26, 18
    hum_opt = 50  # Optimal indoor humidity in %
    hum_max, hum_min = 60, 40
    
    # Normalize temperature deviation
    temp_index = abs(temperature - temp_opt) / (temp_max - temp_min)
    
    # Normalize humidity deviation
    hum_index = abs(humidity - hum_opt) / (hum_max - hum_min)
    
    # Compute IEQI as a weighted sum
    ieqi = 0.5 * icone + 0.3 * temp_index + 0.2 * hum_index
    
    return ieqi

# KPIs CLASSIFICATION
def classify_pmv(pmv):
    """
    Classifies the PMV value into comfort categories from -3 to +3.
    """
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
    """
    Classifies the PPD (Predicted Percentage of Dissatisfied) value based on comfort categories.
    """
    if ppd < 5:
        return "Excellent"  # Almost ideal conditions, <5% dissatisfied
    elif 5 <= ppd < 10:
        return "Good"  # Comfortable range, typical for PMV ~ 0
    elif 10 <= ppd < 25:
        return "Medium"  # Some discomfort, typical for PMV ~ ±1
    elif 25 <= ppd < 75:
        return "Poor"  # Significant discomfort, typical for PMV ~ ±2
    else:
        return "Very Poor"  # Extreme discomfort, almost all dissatisfied (PMV ~ ±3)


def classify_ieqi(ieqi):
    """
    Classify IEQI value into categories.
    """
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
    """
    Classify ICONE value into categories.
    """
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

