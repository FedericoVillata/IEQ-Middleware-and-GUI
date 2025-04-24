# apartment_processor.py

from publisher_service import (
    publish_room_metrics,
    publish_tenant_suggestions,
    publish_technical_suggestions,
    publish_alerts,
)

from data_fetcher import fetch_data, fetch_feedback  
from tenant_suggestions import get_tenant_suggestions, detect_trend  
from technical_suggestions import get_technical_suggestions
from kpis_classification import *

import numpy as np
from datetime import datetime

def log(message, level="INFO", context=None):
    timestamp = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    prefix = f"[{timestamp}] [{level}]"
    # prefix = f"[{level}]"
    if context:
        prefix += f" [{context}]"
    print(f"{prefix} {message}")


def process_apartment(apartment, catalog, weather_info, publisher,
                      base_topic, adaptor_base, base_settings=None):
    apartment_id = apartment['apartmentId']
    log("Processing apartment", context=apartment_id)

    if base_settings is None:
        base_settings = catalog.get("base_settings")
    settings = apartment.get("settings", base_settings)
    season = "warm" if 4 <= datetime.now().month <= 9 else "cold"

    for room in apartment["rooms"]:
        room_id = room["roomId"]
        log("Processing room", context=f"{apartment_id}/{room_id}")

        user_id = apartment["users"][0]
        measures = ["Temperature", "Humidity", "CO2", "PM10", "VOC"]
        measure_data = {}

        for measure in measures:
            fetched = fetch_data(adaptor_base, user_id, apartment_id, measure, duration="168")
            if not fetched:
                log(f"No data fetched for {measure}", level="WARN", context=f"{apartment_id}/{room_id}")
                continue
            room_filtered = [e for e in fetched if e.get("room") == room_id]
            measure_data[measure] = room_filtered

        if any(not measure_data.get(m) for m in ["Temperature", "Humidity", "CO2"]):
            log("Missing Temperature/Humidity/CO2 data, skipping room", level="WARN", context=f"{apartment_id}/{room_id}")
            continue

        # Compute averages
        avg_temp = np.mean([d["v"] for d in measure_data["Temperature"]])
        avg_humidity = np.mean([d["v"] for d in measure_data["Humidity"]])
        avg_co2 = np.mean([d["v"] for d in measure_data["CO2"]])
        avg_pm10 = np.mean([d["v"] for d in measure_data.get("PM10", [])]) if measure_data.get("PM10") else None
        avg_tvoc = np.mean([d["v"] for d in measure_data.get("VOC", [])]) if measure_data.get("VOC") else None

        # Trends
        trends = {
            "temperature": detect_trend([d["v"] for d in measure_data["Temperature"]][-3:]),
            "humidity": detect_trend([d["v"] for d in measure_data["Humidity"]][-3:]),
            "co2": detect_trend([d["v"] for d in measure_data["CO2"]][-3:]),
            "voc": detect_trend([d["v"] for d in measure_data.get("VOC", [])][-3:] if measure_data.get("VOC") else []),
            "pm10": detect_trend([d["v"] for d in measure_data.get("PM10", [])][-3:] if measure_data.get("PM10") else [])
        }

        # Comfort classification
        outdoor_temps = [d.get("outdoor_temp", avg_temp) for d in measure_data["Temperature"]][-7:]
        adaptive_comfort = adaptive_thermal_comfort(outdoor_temps)
        t_ext = adaptive_comfort['Running Mean Temperature'] if adaptive_comfort else avg_temp
        cat_num = settings["thresholds"].get("adaptive_temp_category", 2)
        cat_label = f"Cat {'I' if cat_num == 1 else 'II' if cat_num == 2 else 'III'}"
        adaptive_range = adaptive_comfort["Acceptable Range"].get(cat_label) if adaptive_comfort else None

        if not adaptive_range:
            log(f"Missing adaptive range for {cat_label}, skipping room", level="WARN", context=f"{apartment_id}/{room_id}")
            continue

        temp_class = classify_temperature(avg_temp, season, t_ext, settings, adaptive_range)
        hum_class = classify_humidity(avg_humidity, settings)
        co2_class = classify_co2(avg_co2, settings)
        pmv = calculate_pmv(season, avg_temp, avg_temp, 0.1, avg_humidity, settings)
        pmv_class = classify_pmv(pmv, settings)
        ppd = calculate_ppd(pmv)
        ppd_class = classify_ppd(ppd, settings)

        icone = ieqi = icone_class = ieqi_class = None
        if avg_pm10 is not None and avg_tvoc is not None:
            icone = calculate_icone(avg_co2, avg_pm10, avg_tvoc)
            icone_class = classify_icone(icone, settings)
            ieqi = calculate_ieqi(icone, avg_temp, avg_humidity, settings)
            ieqi_class = classify_ieqi(ieqi, settings)

        classifications = {
            "temperature": temp_class,
            "humidity": hum_class,
            "co2": co2_class,
            "pmv": pmv_class,
            "ppd": ppd_class
        }
        if icone_class: classifications["icone"] = icone_class
        if ieqi_class: classifications["ieqi"] = ieqi_class

        env_score = overall_score(classifications, settings)
        env_class = classify_overall_score(env_score, settings)
        classifications["overall_score"] = env_class

        # Prepare context for suggestions
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

        enabled_ids = {s["suggestionId"] for s in room.get("suggestions", []) if s.get("state", 0) == 1}
        id_to_name = {s["suggestionId"]: s["suggestionName"] for s in catalog.get("tenant_suggestions", [])}
        enabled_names = {id_to_name.get(sid) for sid in enabled_ids if id_to_name.get(sid)}

        tenant_suggestions = get_tenant_suggestions(
            classifications=classifications,
            temp=avg_temp,
            humidity=avg_humidity,
            co2=avg_co2,
            t_ext=t_ext,
            hour=datetime.now().hour,
            pmv=pmv,
            trends=trends,
            settings=suggestion_settings,
            enabled_suggestions=enabled_names
        )

        if tenant_suggestions:
                log(f"Generated {len(tenant_suggestions)} tenant suggestions", context=f"{apartment_id}/{room_id}")

        feedback = fetch_feedback(adaptor_base, user_id, apartment_id, room_id)

        tech_suggestions = get_technical_suggestions(
            classifications=classifications,
            feedback=feedback,
            metrics={
                "temperature": avg_temp,
                "humidity": avg_humidity,
                "co2": avg_co2,
                "pmv": pmv,
                "ppd": ppd,
                "voc": avg_tvoc,
                "pm10": avg_pm10,
                "icone": icone,
                "ieqi": ieqi,
                "overall_score": env_score,
                "t_ext": t_ext
            },
            settings=suggestion_settings
        )

        publish_room_metrics(publisher, base_topic, apartment_id, room_id, {
            "avg_temp": avg_temp,
            "avg_humidity": avg_humidity,
            "avg_co2": avg_co2,
            "pmv": pmv,
            "ppd": ppd,
            "icone": icone,
            "ieqi": ieqi,
            "temp_class": temp_class,
            "hum_class": hum_class,
            "co2_class": co2_class,
            "pmv_class": pmv_class,
            "ppd_class": ppd_class,
            "icone_class": icone_class,
            "ieqi_class": ieqi_class,
            "adaptive_comfort": adaptive_comfort,
            "env_score": env_score,
            "env_classification": env_class
        })

        publish_alerts(publisher, base_topic, apartment_id, room_id, classifications)
        publish_tenant_suggestions(publisher, base_topic, apartment_id, room_id, tenant_suggestions)
        publish_technical_suggestions(publisher, base_topic, apartment_id, room_id, tech_suggestions)

        log("Finished processing room", context=f"{apartment_id}/{room_id}")
