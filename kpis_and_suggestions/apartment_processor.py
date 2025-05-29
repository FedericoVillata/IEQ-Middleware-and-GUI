# apartment_processor.py
from datetime import datetime, timedelta
from collections import defaultdict, Counter

from publisher_service import (
    publish_room_metrics,
    publish_tenant_suggestions,
    publish_technical_suggestions,
    publish_alerts,
)

from data_fetcher import fetch_data, fetch_feedback, fetch_daily_exterior_temps  
from tenant_suggestions import get_tenant_suggestions, detect_trend  
from technical_suggestions import get_technical_suggestions
from kpis_classification import *
from weather_service import get_past_7days_weather

import numpy as np
from datetime import datetime, timedelta
from zoneinfo import ZoneInfo 

# Map labels to scores for each classification category
LABEL_SCORE_MAP = {
    "temp_class": {
        "Extreme": 0,
        "R": 1,
        "Y": 2,
        "G": 4
    },
    "hum_class": {
        "Extreme": 0,
        "R": 1,
        "Y": 2,
        "G": 4
    },
    "co2_class": {
        "Extreme": 0,
        "R": 1,
        "Y": 2,
        "G": 3,
        "Too Good": 4
    },
    "pmv_class": {
        "Very Cold": 0,
        "Cold": 1,
        "Slightly Cold": 2,
        "Neutral": 4,
        "Slightly Warm": 2,
        "Warm": 1,
        "Very Warm": 0
    },
    "ppd_class": {
        "Extreme": 0,
        "R": 1,
        "Y": 2,
        "G": 4
    },
    "icone_class": {
        "R": 1,
        "Y": 2,
        "G": 4
    },
    "ieqi_class": {
        "R": 1,
        "Y": 2,
        "G": 4
    },
    "env_score": {
        "R": 1,
        "Y": 2,
        "G": 4
    }
}



def log(message, level="INFO", context=None):
    timestamp = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    prefix = f"[{timestamp}] [{level}]"
    # prefix = f"[{level}]"
    if context:
        prefix += f" [{context}]"
    print(f"{prefix} {message}")


def parse_isoformat_safe(iso_str):
    # Convert ISO 8601 with 'Z' to a format accepted by datetime
    if isinstance(iso_str, str) and iso_str.endswith('Z'):
        iso_str = iso_str[:-1] + '+00:00'
    try:
        return datetime.fromisoformat(iso_str)
    except Exception:
        return None

def check_sensor_updates(room, apartment_timezone, threshold_minutes=24 * 60):
    try:
        now = datetime.now(ZoneInfo(apartment_timezone)) 
    except Exception:
        now = datetime.utcnow()

    alerts = []

    threshold_delta = timedelta(minutes=threshold_minutes)

    for sensor in room.get("sensors", []):
        sensor_id = sensor.get("sensorId")
        last_update = sensor.get("lastUpdate")
        if not sensor_id or not last_update:
            continue

        parsed_last_update = parse_isoformat_safe(last_update)
        if not parsed_last_update:
            continue

        time_diff = now - parsed_last_update
        if parsed_last_update.tzinfo is None:
            log(f"Warning: parsed_last_update has no tzinfo — {parsed_last_update}", level="WARN")

        if time_diff > threshold_delta:
            measurements = sensor.get("measurements", [])
            if measurements:
                sensor_measurement = ", ".join(measurements)
            else:
                sensor_measurement = "Unknown measurement"

            hours, remainder = divmod(int(time_diff.total_seconds()), 3600)
            minutes = remainder // 60
            time_ago = f"{hours}h {minutes}min" if hours > 0 else f"{minutes}min"

            alert_msg = (
                f"Check the status of sensor {sensor_id} (battery, device failure). "
                f"No {sensor_measurement} data received for {time_ago}."
            )

            alerts.append({
                "sensor_name": f"{room['roomId']}/{sensor_id}",
                "message": alert_msg
            })

    return alerts

def process_apartment(apartment, catalog, weather_info, publisher,
                      base_topic, adaptor_base, base_settings=None, first_iteration=False):
    apartment_id = apartment['apartmentId']
    coords = apartment.get("coordinates", {})
    lat, lon = coords.get("lat"), coords.get("long")
    log(f"Apartment {apartment_id} coordinates: {coords}", context=apartment_id)
    apartment_timezone = apartment.get("timezone", catalog.get("timezone", "UTC"))

    log("Processing apartment", context=apartment_id)

    if base_settings is None:
        base_settings = catalog.get("base_settings")
    settings = apartment.get("settings", base_settings)

    season = "warm" if 4 <= datetime.now().month <= 9 else "cold"
    user_list = apartment.get("users", [])
    if not user_list:
        log("No user associated with apartment, skipping", level="ERROR", context=apartment.get("apartmentId"))
        return
    user_id = user_list[0]

    # --- Get exterior room temperature series if available ---
    external_temp_series = []

    # Check if apartment has exterior sensor
    has_exterior_sensor = any(room.get("roomId") == "exterior" for room in apartment.get("rooms", []))

    if has_exterior_sensor:
        external_temp_series = fetch_daily_exterior_temps(adaptor_base, user_id, apartment_id)
        log(f"Using daily exterior temperatures: {external_temp_series}", context=apartment_id)

    if external_temp_series and len(external_temp_series) < 7:
        log(f"Sensor data has only {len(external_temp_series)} values, completing with weather data", context=apartment_id)
        if lat is not None and lon is not None:
            weather_data = get_past_7days_weather(lat, lon)
            needed = 7 - len(external_temp_series)
            external_temp_series += weather_data[-needed:]
            log(f"Completed sensor data with weather data: {external_temp_series}", context=apartment_id)
        else:
            log("No coordinates available, cannot complete with weather data", level="WARN", context=apartment_id)

    if not external_temp_series:
        if lat is not None and lon is not None:
            external_temp_series = get_past_7days_weather(lat, lon)
            log(f"Using fallback weather temperature series: {external_temp_series}", context=apartment_id)
        else:
            log("No coordinates available, using default fallback temperature", level="WARN", context=apartment_id)
            fallback_temp = weather_info.get("temperature", -999)
            external_temp_series = [fallback_temp] * 7



    feedback = fetch_feedback(adaptor_base, user_id, apartment_id)

    # ROOM DATA AGGREGATION BY APARTMENT
    # Dictionary to collect all room classifications grouped by category (e.g., temp_class, co2_class, etc.)
    apartment_classifications = defaultdict(list)

    # Dictionary to store numeric metrics (e.g., temperature, humidity) for the apartment
    apartment_metrics = defaultdict(list)

    # Dictionary to count how many times each classification label (G, Y, R, etc.) appears per category
    label_counter = defaultdict(Counter)

    # Loop through each room in the apartment
    for room in apartment["rooms"]:
        if room.get("roomId") == "exterior":
            continue

        result = process_room(
            room,
            apartment_id,
            apartment_timezone,
            user_id,
            adaptor_base,
            catalog,
            settings,
            season,
            weather_info,
            external_temp_series,
            publisher,
            base_topic,
            first_iteration=first_iteration
        )

        # If the room returned valid results
        if result:
            classif, metrics = result

            # Aggregate classification labels and count their occurrences
            for category, label in classif.items():
                apartment_classifications[category].append(label)
                label_counter[category][label] += 1

            # Collect only valid (non-None) numeric values for averaging later
            for metric_name, value in metrics.items():
                if value is not None:
                    apartment_metrics[metric_name].append(value)



    generate_technical_suggestions(
        apartment_id, apartment_classifications,
        apartment_metrics, label_counter, feedback, settings,
        weather_info, publisher, base_topic
    )

def process_room(room, apartment_id, apartment_timezone, user_id, adaptor_base, catalog, settings,
                 season, weather_info, external_temp_series, publisher, base_topic, first_iteration=False):
    room_id = room["roomId"]
    log("Processing room", context=f"{apartment_id}/{room_id}")
    if not publisher._paho_mqtt.is_connected():
        log("MQTT disconnected, trying to reconnect...", level="WARN", context=f"{apartment_id}/{room_id}")
        publisher._paho_mqtt.reconnect()


    data = fetch_room_data(room_id, apartment_id, user_id, adaptor_base)
    if not data:
        log("Missing Temperature/Humidity/CO2 data", level="WARN", context=f"{apartment_id}/{room_id}")
        return None

    avg_values, trends = compute_room_averages(data)
    classifications, t_ext_rm, icone, ieqi, adaptive_comfort = classify_room_conditions(
        avg_values, trends, data, settings, season, weather_info, external_temp_series
    )


    if not classifications or not isinstance(classifications, dict):
        return None
    
    # Keys' mapping from _class to standard
    mapped_classifications = {
    "temperature": classifications.get("temp_class"),
    "humidity": classifications.get("hum_class"),
    "co2": classifications.get("co2_class"),
    "pmv": classifications.get("pmv_class"),
    "ppd": classifications.get("ppd_class"),
    "icone": classifications.get("icone_class"),
    "ieqi": classifications.get("ieqi_class"),
    }

    pmv = calculate_pmv(season, avg_values["avg_temp"], avg_values["avg_temp"], 0.1, avg_values["avg_humidity"], settings)
    ppd = calculate_ppd(pmv)

    kpi_values = {
        "temperature": avg_values["avg_temp"],
        "humidity": avg_values["avg_humidity"],
        "co2": avg_values["avg_co2"],
        "pmv": pmv,
        "ppd": ppd,
        "icone": icone,
        "ieqi": ieqi
    }

    # Select the correct temperature/co2 thresholds based on ventilation and season
    vent = settings["values"].get("ventilation")
    if vent == "nat":
        co2_thr = settings["thresholds"]["co2_natural"]
        acceptable = adaptive_comfort["Acceptable Range"]
        cat_num = settings["thresholds"].get("adaptive_temp_category", 2)

        # Map category number to label
        cat_label_map = {1: "Cat I", 2: "Cat II", 3: "Cat III"}
        cat_label = cat_label_map.get(cat_num, "Cat II")

        # Get G range from selected category
        g_min, g_max = acceptable[cat_label]

        # Try to get a wider range for Y (use Cat III as fallback)
        if cat_label != "Cat III":
            y_min, y_max = acceptable["Cat III"]
        else:
            # Expand artificially by ±1 if already at Cat III
            y_min, y_max = g_min - 1, g_max + 1

        # Define thresholds
        temp_thr = {
            "G": [g_min, g_max],
            "Y": [y_min, y_max],
            "R": [-50, y_min, y_max, 100]
        }
    else:
        co2_thr = settings["thresholds"]["co2_mechanical"]
        key = f"mechanical_temp_{season}"
        temp_thr = settings["thresholds"][key]

    cont_thresholds = {
        "temperature": temp_thr,
        "humidity": settings["thresholds"]["humidity"],
        "co2": co2_thr,
        "pmv": settings["thresholds"]["pmv_classification"],
        "ppd": settings["thresholds"]["ppd_classification"],
        "icone": settings["thresholds"]["icone_classification"],
        "ieqi": settings["thresholds"]["ieqi_classification"]
    }

    new_settings=settings.copy()
    new_settings["thresholds"]=cont_thresholds

    env_score = overall_score_continuous(kpi_values, new_settings)
    env_class = classify_overall_score(env_score, settings)

    mapped_classifications["overall_score"] = env_class

    suggestions = generate_room_suggestions(
        room, catalog, mapped_classifications, avg_values, t_ext_rm, settings,
        season, weather_info, trends
        )
    
    log(
        f"Publishing KPIs | Apartment: {apartment_id} | "
        f"Room: {room_id} | PMV: {pmv:.2f} | PPD: {ppd:.2f}",
        level="INFO"
    )

    publish_detailed_room_metrics(
        publisher,
        base_topic,
        apartment_id,
        room_id,
        avg_values=avg_values,
        classifications=classifications,
        pmv=pmv,
        ppd=ppd,
        icone=icone if 'icone_class' in classifications else None,
        ieqi=ieqi if 'ieqi_class' in classifications else None,
        adaptive_comfort=adaptive_comfort if 'Acceptable Range' in adaptive_comfort else None,
        env_score=env_score,
        env_class=env_class
    )

    sensor_alerts = check_sensor_updates(room, apartment_timezone)
    if not first_iteration:
        publish_alerts(publisher, base_topic, apartment_id, room_id, classifications, sensor_alerts=sensor_alerts)
    else:
        log("Skipping alert publication on first iteration", level="DEBUG", context=f"{apartment_id}/{room_id}")

    publish_tenant_suggestions(publisher, base_topic, apartment_id, room_id, suggestions)

    log("Finished processing room", context=f"{apartment_id}/{room_id}")

    return classifications, {
        "temperature": avg_values["avg_temp"],
        "humidity": avg_values["avg_humidity"],
        "t_ext": t_ext_rm
    }

def fetch_room_data(room_id, apartment_id, user_id, adaptor_base):
    measures = ["Temperature", "Humidity", "CO2", "PM10.0", "VOC"]
    measure_data = {}

    for measure in measures:
        fetched = fetch_data(adaptor_base, user_id, apartment_id, measure)
        if not fetched:
            log(f"No data fetched for {measure}", level="WARN", context=f"{apartment_id}/{room_id}")
            continue
        room_filtered = [e for e in fetched if e.get("room") == room_id]
        measure_data[measure] = room_filtered

    # Verify the presence of essential data
    if any(not measure_data.get(m) for m in ["Temperature", "Humidity", "CO2"]):
        return None

    return measure_data

def compute_room_averages(measure_data):
    def average(measurements):
        return np.mean([d["v"] for d in measurements]) if measurements else None

    def last_n(data, n=3):
        return data[-n:] if len(data) >= n else data

    avg_temp = average(measure_data.get("Temperature", []))
    avg_humidity = average(measure_data.get("Humidity", []))
    avg_co2 = average(measure_data.get("CO2", []))
    avg_pm10 = average(measure_data.get("PM10.0", []))
    avg_tvoc = average(measure_data.get("VOC", []))

    trends = {
        "temperature": detect_trend(last_n([d["v"] for d in measure_data.get("Temperature", [])])),
        "humidity": detect_trend(last_n([d["v"] for d in measure_data.get("Humidity", [])])),
        "co2": detect_trend(last_n([d["v"] for d in measure_data.get("CO2", [])])),
        "voc": detect_trend(last_n([d["v"] for d in measure_data.get("VOC", [])])),
        "pm10": detect_trend(last_n([d["v"] for d in measure_data.get("PM10", [])])),
    }

    avg_values = {
        "avg_temp": avg_temp,
        "avg_humidity": avg_humidity,
        "avg_co2": avg_co2,
        "avg_pm10": avg_pm10,
        "avg_tvoc": avg_tvoc
    }

    return avg_values, trends

def classify_room_conditions(avg_values, trends, measure_data, settings, season, weather_info, external_temp_series):
    avg_temp = avg_values["avg_temp"]
    avg_humidity = avg_values["avg_humidity"]
    avg_co2 = avg_values["avg_co2"]
    avg_pm10 = avg_values["avg_pm10"]
    avg_tvoc = avg_values["avg_tvoc"]

    if avg_temp is None or avg_humidity is None or avg_co2 is None:
        return None, None, None, None, None

    outdoor_temps = external_temp_series[-7:] if len(external_temp_series) >= 7 else external_temp_series
    if len(outdoor_temps) < 7:
        log(f"Only {len(outdoor_temps)} outdoor temps available, padding with last value", level="WARN", context="adaptive_comfort")
        if outdoor_temps:
            outdoor_temps += [outdoor_temps[-1]] * (7 - len(outdoor_temps))
        else:
            outdoor_temps = [avg_temp] * 7 

    adaptive_comfort = adaptive_thermal_comfort(outdoor_temps)

    if not adaptive_comfort:
        return None, None, None, None, None

    running_mean_temp = adaptive_comfort.get("Running Mean Temperature", avg_temp)
    cat_num = settings["thresholds"].get("adaptive_temp_category", 2)
    cat_label = f"Cat {'I' if cat_num == 1 else 'II' if cat_num == 2 else 'III'}"
    adaptive_range = adaptive_comfort["Acceptable Range"].get(cat_label)
    if not adaptive_range:
        return None, None, None, None, None
    # Classifications
    temp_class = classify_temperature(avg_temp, season, running_mean_temp, settings, adaptive_range)
    hum_class = classify_humidity(avg_humidity, settings)
    co2_class = classify_co2(avg_co2, settings)

    pmv = calculate_pmv(season, avg_temp, avg_temp, 0.1, avg_humidity, settings)
    pmv_class = classify_pmv(pmv, settings)
    ppd = calculate_ppd(pmv)
    ppd_class = classify_ppd(ppd, settings)

    icone = ieqi = icone_class = ieqi_class = None
    if any(v is not None for v in [avg_co2, avg_pm10, avg_tvoc]):
        log(f"Calculating ICONE with: co2={avg_co2}, pm10={avg_pm10}, tvoc={avg_tvoc}", level="DEBUG", context="calculate_icone")
        icone = calculate_icone(avg_co2, avg_pm10, avg_tvoc)
        icone_class = classify_icone(icone, settings)
        ieqi = calculate_ieqi(icone, avg_temp, avg_humidity, settings)
        ieqi_class = classify_ieqi(ieqi, settings)

    classifications = {
        "temp_class": temp_class,
        "hum_class": hum_class,
        "co2_class": co2_class,
        "pmv_class": pmv_class,
        "ppd_class": ppd_class
    }

    if icone_class:
        classifications["icone_class"] = icone_class
    if ieqi_class:
        classifications["ieqi_class"] = ieqi_class

    return classifications, running_mean_temp, icone, ieqi, adaptive_comfort


def generate_room_suggestions(room, catalog, classifications, avg_values, t_ext,
                              settings, season, weather_info, trends):

    hour_now = datetime.now().hour

    context_values = dict(settings.get("values", {}))
    context_values.update({
        "season": season,
        "weather": "rain" if weather_info.get("weather_code") in {61, 63, 65, 80, 81, 82} else "clear",
        "forecast": {
            "sunny": weather_info.get("sunny", False),
            "bad_days": weather_info.get("bad_days", 0),
            "temp_drop": weather_info.get("temp_drop", False)
        }
    })

    suggestion_settings = dict(settings)
    suggestion_settings["values"] = context_values

    # Get enabled tenant suggestion names for this room
    suggestions_list = room.get("suggestions", [])
    if not isinstance(suggestions_list, list):
        log("Invalid 'suggestions' structure", level="WARN", context=room.get("roomId"))
        suggestions_list = []

    enabled_ids = {s["suggestionId"] for s in suggestions_list if s.get("state", 0) == 1}
    name_to_id = {s["suggestionName"]: s["suggestionId"] for s in catalog.get("tenant_suggestions", [])}

    tenant_suggestions = get_tenant_suggestions(
        classifications=classifications,
        temp=avg_values["avg_temp"],
        humidity=avg_values["avg_humidity"],
        co2=avg_values["avg_co2"],
        t_ext=t_ext,
        hour=hour_now,
        pmv=calculate_pmv(season, avg_values["avg_temp"], avg_values["avg_temp"], 0.1, avg_values["avg_humidity"], settings),
        trends=trends,
        settings=suggestion_settings,
        enabled_suggestions=enabled_ids,  
        name_to_id=name_to_id                
    )

    if tenant_suggestions:
        log(f"Generated {len(tenant_suggestions)} tenant suggestions", context=room["roomId"])

    return tenant_suggestions

def generate_technical_suggestions(apartment_id, apartment_classifications,
                                   apartment_metrics, label_counter, feedback, 
                                   settings, weather_info, publisher, base_topic):
    
    def safe_mean(values):
        valid = [v for v in values if v is not None]
        return np.mean(valid) if valid else None
    
    def reduce_class(label_count: Counter, category,
                    guard_ratio: float = 0.45) -> str:
        """
        Hybrid reducer:
        1. Compute severity score (G=4 … Extreme=0) based on LABEL_SCORE_MAP.
        2. Map average score back to a label.
        3. Guard-rail: if >= guard_ratio of rooms are 'R'
        or any room is 'Extreme', override result.
        """
        if not label_count:
            return "Unknown"

        # --- numeric score ------------------------------------------
        label_to_score = LABEL_SCORE_MAP.get(category)

        if not label_to_score:
            return "Unknown"  

        total = sum(label_count.values())
        critical_ratio = label_count.get("R", 0) / total
        if label_count.get("Extreme", 0) > 0:
            return "Extreme"
        if critical_ratio >= guard_ratio:
            return "R"
        severity_sum = sum(label_to_score.get(label, 0) * count for label, count in label_count.items())
        avg_score = severity_sum / total

        # Define score thresholds dynamically if needed, or use static rules
        if category == "pmv_class":
            if   avg_score <= 0.5: return "Very Cold"
            elif avg_score <= 1.5: return "Cold"
            elif avg_score <= 2.5: return "Slightly Cold"
            elif avg_score <= 3.5: return "Neutral"
            elif avg_score <= 3.9: return "Slightly Warm"
            elif avg_score <= 4.1: return "Warm"
            else:                  return "Very Warm"
        else:
            if   avg_score >= 2.5: return "G"
            elif avg_score >= 1.5: return "Y"
            elif avg_score >= 0.5: return "R"
            else: return "Extreme"



    reduced_classifications = {
        k: reduce_class(label_counter[k], category=k)
        for k in apartment_classifications
    }

    avg_temp = safe_mean(apartment_metrics["temperature"])
    avg_t_ext = safe_mean(apartment_metrics["t_ext"])

    t_int = avg_temp
    t_ext = (
        avg_t_ext
        if avg_t_ext is not None
        else weather_info.get("temperature")
        if weather_info else
        t_int                                     
    )

    # --- Maps classes' name to key expected from the function --- 
    class_map = {
        "temperature":   reduced_classifications.get("temp_class"),
        "humidity":      reduced_classifications.get("hum_class"),
        "pmv":           reduced_classifications.get("pmv_class"),
        "overall_score": reduced_classifications.get("env_score") or "Unknown",
    }

    tech_suggestions = get_technical_suggestions(
        classifications=class_map,
        feedback=feedback,
        metrics={
            "temperature": t_int,
            "humidity": safe_mean(apartment_metrics["humidity"]),
            "t_ext": t_ext
        },
        settings=settings
    )

    publish_technical_suggestions(
        publisher,
        base_topic,
        apartment_id,
        tech_suggestions
    )

    log(f"Published {len(tech_suggestions)} technical suggestions at apartment level", context=apartment_id)

def publish_detailed_room_metrics(publisher, base_topic, apartment_id, room_id,
                                avg_values, classifications, pmv, ppd,
                                icone=None, ieqi=None, adaptive_comfort=None, env_score=None, env_class=None):
    metrics_payload = {
        "avg_temp": avg_values.get("avg_temp"),
        "avg_humidity": avg_values.get("avg_humidity"),
        "avg_co2": avg_values.get("avg_co2"),
        "avg_pm10": avg_values.get("avg_pm10"),
        "avg_tvoc": avg_values.get("avg_tvoc"),
        "pmv": pmv,
        "ppd": ppd,
        "icone": icone,
        "ieqi": ieqi,
        "temp_class": classifications.get("temp_class"),
        "hum_class": classifications.get("hum_class"),
        "co2_class": classifications.get("co2_class"),
        "pmv_class": classifications.get("pmv_class"),
        "ppd_class": classifications.get("ppd_class"),
        "icone_class": classifications.get("icone_class"),
        "ieqi_class": classifications.get("ieqi_class"),
        "adaptive_comfort": adaptive_comfort,
        "env_score": env_score,
        "env_classification": env_class
    }
    publish_room_metrics(publisher, base_topic, apartment_id, room_id, metrics_payload)
