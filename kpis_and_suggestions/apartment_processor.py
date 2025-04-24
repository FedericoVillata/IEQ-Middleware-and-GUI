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
    user_id = apartment["users"][0]
    feedback = fetch_feedback(adaptor_base, user_id, apartment_id)

    apartment_classifications = {}
    apartment_metrics = {
        "temperature": [],
        "humidity": [],
        "t_ext": []
    }

    for room in apartment["rooms"]:
        result = process_room(room, apartment_id, user_id, adaptor_base, catalog,
                              settings, season, weather_info, publisher, base_topic)
        if result:
            classif, metrics = result
            for k, v in classif.items():
                apartment_classifications.setdefault(k, []).append(v)
            for k, v in metrics.items():
                apartment_metrics[k].append(v)

    generate_technical_suggestions(
        apartment_id, apartment_classifications,
        apartment_metrics, feedback, settings,
        weather_info, publisher, base_topic
    )

def process_room(room, apartment_id, user_id, adaptor_base, catalog, settings,
                 season, weather_info, publisher, base_topic):
    room_id = room["roomId"]
    log("Processing room", context=f"{apartment_id}/{room_id}")

    data = fetch_room_data(room_id, apartment_id, user_id, adaptor_base)
    if not data:
        log("Missing Temperature/Humidity/CO2 data", level="WARN", context=f"{apartment_id}/{room_id}")
        return None

    avg_values, trends = compute_room_averages(data)
    classifications, t_ext, icone, ieqi, adaptive_comfort = classify_room_conditions(
        avg_values, trends, data, settings, season
    )


    if not classifications:
        return None

    suggestions = generate_room_suggestions(
        room, catalog, classifications, avg_values, t_ext, settings,
        season, weather_info, trends
    )


    pmv = calculate_pmv(season, avg_values["avg_temp"], avg_values["avg_temp"], 0.1, avg_values["avg_humidity"], settings)
    ppd = calculate_ppd(pmv)
    env_score = overall_score(classifications, settings)
    env_class = classify_overall_score(env_score, settings)

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


    publish_alerts(publisher, base_topic, apartment_id, room_id, classifications)
    publish_tenant_suggestions(publisher, base_topic, apartment_id, room_id, suggestions)

    log("Finished processing room", context=f"{apartment_id}/{room_id}")

    return classifications, {
        "temperature": avg_values["avg_temp"],
        "humidity": avg_values["avg_humidity"],
        "t_ext": t_ext
    }

def fetch_room_data(room_id, apartment_id, user_id, adaptor_base):
    measures = ["Temperature", "Humidity", "CO2", "PM10", "VOC"]
    measure_data = {}

    for measure in measures:
        fetched = fetch_data(adaptor_base, user_id, apartment_id, measure, duration="168")
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

    avg_temp = average(measure_data.get("Temperature", []))
    avg_humidity = average(measure_data.get("Humidity", []))
    avg_co2 = average(measure_data.get("CO2", []))
    avg_pm10 = average(measure_data.get("PM10", []))
    avg_tvoc = average(measure_data.get("VOC", []))

    trends = {
        "temperature": detect_trend([d["v"] for d in measure_data["Temperature"]][-3:]),
        "humidity": detect_trend([d["v"] for d in measure_data["Humidity"]][-3:]),
        "co2": detect_trend([d["v"] for d in measure_data["CO2"]][-3:]),
        "voc": detect_trend([d["v"] for d in measure_data.get("VOC", [])][-3:] if measure_data.get("VOC") else []),
        "pm10": detect_trend([d["v"] for d in measure_data.get("PM10", [])][-3:] if measure_data.get("PM10") else [])
    }

    avg_values = {
        "avg_temp": avg_temp,
        "avg_humidity": avg_humidity,
        "avg_co2": avg_co2,
        "avg_pm10": avg_pm10,
        "avg_tvoc": avg_tvoc
    }

    return avg_values, trends

def classify_room_conditions(avg_values, trends, measure_data, settings, season):
    avg_temp = avg_values["avg_temp"]
    avg_humidity = avg_values["avg_humidity"]
    avg_co2 = avg_values["avg_co2"]
    avg_pm10 = avg_values["avg_pm10"]
    avg_tvoc = avg_values["avg_tvoc"]

    if avg_temp is None or avg_humidity is None or avg_co2 is None:
        return None, None

    # Determine adaptive comfort
    outdoor_temps = [d.get("outdoor_temp", avg_temp) for d in measure_data["Temperature"]][-7:]
    adaptive_comfort = adaptive_thermal_comfort(outdoor_temps)
    if not adaptive_comfort:
        return None, None

    running_mean_temp = adaptive_comfort.get("Running Mean Temperature", avg_temp)
    cat_num = settings["thresholds"].get("adaptive_temp_category", 2)
    cat_label = f"Cat {'I' if cat_num == 1 else 'II' if cat_num == 2 else 'III'}"
    adaptive_range = adaptive_comfort["Acceptable Range"].get(cat_label)
    if not adaptive_range:
        return None, None

    # Classifications
    temp_class = classify_temperature(avg_temp, season, running_mean_temp, settings, adaptive_range)
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
        "temp_class": temp_class,
        "hum_class": hum_class,
        "co2_class": co2_class,
        "pmv_class": pmv_class,
        "ppd_class": ppd_class,
        "env_score": classify_overall_score(overall_score({
            "temperature": temp_class,
            "humidity": hum_class,
            "co2": co2_class,
            "pmv": pmv_class,
            "ppd": ppd_class,
            **({"icone": icone_class} if icone_class else {}),
            **({"ieqi": ieqi_class} if ieqi_class else {})
        }, settings), settings)
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
    enabled_ids = {s["suggestionId"] for s in room.get("suggestions", []) if s.get("state", 0) == 1}
    id_to_name = {s["suggestionId"]: s["suggestionName"] for s in catalog.get("tenant_suggestions", [])}
    enabled_names = {id_to_name.get(sid) for sid in enabled_ids if id_to_name.get(sid)}

    tenant_suggestions = get_tenant_suggestions(
        classifications=classifications,
        temp=avg_values["avg_temp"],
        humidity=avg_values["avg_humidity"],
        co2=avg_values["avg_co2"],
        t_ext=t_ext,
        hour=hour_now,
        pmv=calculate_pmv(season, avg_values["avg_temp"], avg_values["avg_temp"], 0.1,
                          avg_values["avg_humidity"], settings),
        trends=trends,
        settings=suggestion_settings,
        enabled_suggestions=enabled_names
    )

    if tenant_suggestions:
        log(f"Generated {len(tenant_suggestions)} tenant suggestions", context=room["roomId"])

    return tenant_suggestions

def generate_technical_suggestions(apartment_id, apartment_classifications,
                                   apartment_metrics, feedback, settings,
                                   weather_info, publisher, base_topic):
    def reduce_class(class_list):
        # Higher number means more critical
        priority = {
            "G": 1, "Y": 2, "R": 3,
            "Neutral": 1, "Cold": 2, "Hot": 2,
            "Very Cold": 4, "Very Warm": 4, "Extreme": 4
        }
        return max(set(class_list), key=lambda c: priority.get(c, 0))

    reduced_classifications = {
        k: reduce_class(v)
        for k, v in apartment_classifications.items()
    }

    avg_temp = np.mean(apartment_metrics["temperature"])
    avg_hum = np.mean(apartment_metrics["humidity"])
    avg_t_ext = np.mean(apartment_metrics["t_ext"])

    tech_suggestions = get_technical_suggestions(
        classifications=reduced_classifications,
        feedback=feedback,
        metrics={
            "temperature": avg_temp,
            "humidity": avg_hum,
            "t_ext": avg_t_ext
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




# # apartment_processor.py

# from publisher_service import (
#     publish_room_metrics,
#     publish_tenant_suggestions,
#     publish_technical_suggestions,
#     publish_alerts,
# )

# from data_fetcher import fetch_data, fetch_feedback  
# from tenant_suggestions import get_tenant_suggestions, detect_trend  
# from technical_suggestions import get_technical_suggestions
# from kpis_classification import *

# import numpy as np
# from datetime import datetime

# def log(message, level="INFO", context=None):
#     timestamp = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
#     prefix = f"[{timestamp}] [{level}]"
#     # prefix = f"[{level}]"
#     if context:
#         prefix += f" [{context}]"
#     print(f"{prefix} {message}")


# def process_apartment(apartment, catalog, weather_info, publisher,
#                       base_topic, adaptor_base, base_settings=None):
#     apartment_id = apartment['apartmentId']
#     log("Processing apartment", context=apartment_id)

#     if base_settings is None:
#         base_settings = catalog.get("base_settings")
#     settings = apartment.get("settings", base_settings)
#     season = "warm" if 4 <= datetime.now().month <= 9 else "cold"

#     user_id = apartment["users"][0]
#     apartment_feedback = fetch_feedback(adaptor_base, user_id, apartment_id)

#     apartment_classifications = {}
#     apartment_metrics = {
#         "temperature": [],
#         "humidity": [],
#         "t_ext": []
#     }


#     for room in apartment["rooms"]:
#         room_id = room["roomId"]
#         log("Processing room", context=f"{apartment_id}/{room_id}")

#         measures = ["Temperature", "Humidity", "CO2", "PM10", "VOC"]
#         measure_data = {}

#         for measure in measures:
#             fetched = fetch_data(adaptor_base, user_id, apartment_id, measure, duration="168")
#             if not fetched:
#                 log(f"No data fetched for {measure}", level="WARN", context=f"{apartment_id}/{room_id}")
#                 continue
#             room_filtered = [e for e in fetched if e.get("room") == room_id]
#             measure_data[measure] = room_filtered

#         if any(not measure_data.get(m) for m in ["Temperature", "Humidity", "CO2"]):
#             log("Missing Temperature/Humidity/CO2 data, skipping room", level="WARN", context=f"{apartment_id}/{room_id}")
#             continue

#         # Compute averages
#         avg_temp = np.mean([d["v"] for d in measure_data["Temperature"]])
#         avg_humidity = np.mean([d["v"] for d in measure_data["Humidity"]])
#         avg_co2 = np.mean([d["v"] for d in measure_data["CO2"]])
#         avg_pm10 = np.mean([d["v"] for d in measure_data.get("PM10", [])]) if measure_data.get("PM10") else None
#         avg_tvoc = np.mean([d["v"] for d in measure_data.get("VOC", [])]) if measure_data.get("VOC") else None

#         # Trends
#         trends = {
#             "temperature": detect_trend([d["v"] for d in measure_data["Temperature"]][-3:]),
#             "humidity": detect_trend([d["v"] for d in measure_data["Humidity"]][-3:]),
#             "co2": detect_trend([d["v"] for d in measure_data["CO2"]][-3:]),
#             "voc": detect_trend([d["v"] for d in measure_data.get("VOC", [])][-3:] if measure_data.get("VOC") else []),
#             "pm10": detect_trend([d["v"] for d in measure_data.get("PM10", [])][-3:] if measure_data.get("PM10") else [])
#         }

#         # Comfort classification
#         outdoor_temps = [d.get("outdoor_temp", avg_temp) for d in measure_data["Temperature"]][-7:]
#         adaptive_comfort = adaptive_thermal_comfort(outdoor_temps)
#         t_ext = adaptive_comfort['Running Mean Temperature'] if adaptive_comfort else avg_temp
#         cat_num = settings["thresholds"].get("adaptive_temp_category", 2)
#         cat_label = f"Cat {'I' if cat_num == 1 else 'II' if cat_num == 2 else 'III'}"
#         adaptive_range = adaptive_comfort["Acceptable Range"].get(cat_label) if adaptive_comfort else None

#         if not adaptive_range:
#             log(f"Missing adaptive range for {cat_label}, skipping room", level="WARN", context=f"{apartment_id}/{room_id}")
#             continue

#         temp_class = classify_temperature(avg_temp, season, t_ext, settings, adaptive_range)
#         hum_class = classify_humidity(avg_humidity, settings)
#         co2_class = classify_co2(avg_co2, settings)
#         pmv = calculate_pmv(season, avg_temp, avg_temp, 0.1, avg_humidity, settings)
#         pmv_class = classify_pmv(pmv, settings)
#         ppd = calculate_ppd(pmv)
#         ppd_class = classify_ppd(ppd, settings)

#         icone = ieqi = icone_class = ieqi_class = None
#         if avg_pm10 is not None and avg_tvoc is not None:
#             icone = calculate_icone(avg_co2, avg_pm10, avg_tvoc)
#             icone_class = classify_icone(icone, settings)
#             ieqi = calculate_ieqi(icone, avg_temp, avg_humidity, settings)
#             ieqi_class = classify_ieqi(ieqi, settings)

#         classifications = {
#             "temperature": temp_class,
#             "humidity": hum_class,
#             "co2": co2_class,
#             "pmv": pmv_class,
#             "ppd": ppd_class
#         }
#         if icone_class: classifications["icone"] = icone_class
#         if ieqi_class: classifications["ieqi"] = ieqi_class

#         env_score = overall_score(classifications, settings)
#         env_class = classify_overall_score(env_score, settings)
#         classifications["overall_score"] = env_class

#         # Prepare context for suggestions
#         context_values = dict(settings.get("values", {}))
#         context_values.update({
#             "season": season,
#             "weather": "rain" if weather_info.get("weather_code") in {61, 63, 65, 80, 81, 82} else "clear",
#             "forecast": {
#                 "sunny": weather_info.get("sunny", False),
#                 "bad_days": weather_info.get("bad_days", 0),
#                 "temp_drop": weather_info.get("temp_drop", False)
#             }
#         })
#         suggestion_settings = dict(settings)
#         suggestion_settings["values"] = context_values

#         enabled_ids = {s["suggestionId"] for s in room.get("suggestions", []) if s.get("state", 0) == 1}
#         id_to_name = {s["suggestionId"]: s["suggestionName"] for s in catalog.get("tenant_suggestions", [])}
#         enabled_names = {id_to_name.get(sid) for sid in enabled_ids if id_to_name.get(sid)}

#         tenant_suggestions = get_tenant_suggestions(
#             classifications=classifications,
#             temp=avg_temp,
#             humidity=avg_humidity,
#             co2=avg_co2,
#             t_ext=t_ext,
#             hour=datetime.now().hour,
#             pmv=pmv,
#             trends=trends,
#             settings=suggestion_settings,
#             enabled_suggestions=enabled_names
#         )

#         if tenant_suggestions:
#                 log(f"Generated {len(tenant_suggestions)} tenant suggestions", context=f"{apartment_id}/{room_id}")

#         # Aggregate classifications
#         for k, v in classifications.items():
#             if k not in apartment_classifications:
#                 apartment_classifications[k] = []
#             apartment_classifications[k].append(v)

#         # Aggregate numeric metrics (for averaging later)
#         apartment_metrics["temperature"].append(avg_temp)
#         apartment_metrics["humidity"].append(avg_humidity)
#         apartment_metrics["t_ext"].append(t_ext)

#         publish_room_metrics(publisher, base_topic, apartment_id, room_id, {
#             "avg_temp": avg_temp,
#             "avg_humidity": avg_humidity,
#             "avg_co2": avg_co2,
#             "pmv": pmv,
#             "ppd": ppd,
#             "icone": icone,
#             "ieqi": ieqi,
#             "temp_class": temp_class,
#             "hum_class": hum_class,
#             "co2_class": co2_class,
#             "pmv_class": pmv_class,
#             "ppd_class": ppd_class,
#             "icone_class": icone_class,
#             "ieqi_class": ieqi_class,
#             "adaptive_comfort": adaptive_comfort,
#             "env_score": env_score,
#             "env_classification": env_class
#         })

#         publish_alerts(publisher, base_topic, apartment_id, room_id, classifications)
#         publish_tenant_suggestions(publisher, base_topic, apartment_id, room_id, tenant_suggestions)

#         log("Finished processing room", context=f"{apartment_id}/{room_id}")

#     # Compute apartment-level average metrics
#     avg_temp = np.mean(apartment_metrics["temperature"])
#     avg_hum = np.mean(apartment_metrics["humidity"])
#     avg_t_ext = np.mean(apartment_metrics["t_ext"])

#     # Use the most critical class if any classification is repeated
#     def reduce_class(class_list):
#         priority = {"R": 3, "Y": 2, "G": 1, "Extreme": 4, "Very Cold": 4, "Very Warm": 4, "Neutral": 1, "Cold": 2, "Hot": 2}
#         return max(set(class_list), key=lambda c: priority.get(c, 0))

#     reduced_classifications = {k: reduce_class(v) for k, v in apartment_classifications.items()}

#     tech_suggestions = get_technical_suggestions(
#         classifications=reduced_classifications,
#         feedback=apartment_feedback,
#         metrics={
#             "temperature": avg_temp,
#             "humidity": avg_hum,
#             "t_ext": avg_t_ext
#         },
#         settings=suggestion_settings
#     )

#     publish_technical_suggestions(
#         publisher,
#         base_topic,
#         apartment_id,
#         tech_suggestions
#     )

#     log(f"Published {len(tech_suggestions)} technical suggestions at apartment level", context=apartment_id)

    
