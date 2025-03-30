import sys
import os
sys.path.append(os.path.abspath(os.path.join(os.path.dirname(__file__), '..')))

import time
import json
import requests
from adaptor.adaptor import *
from kpis_classification import *
#from pubsimulator.pubSimulator import MyPublisher

REGISTRY_URL = 'http://localhost:8080/catalog'
MQTT_BASE_TOPIC = 'home'

def get_catalog():
    try:
        response = requests.get(REGISTRY_URL)
        response.raise_for_status()
        return response.json()
    except requests.RequestException as e:
        print(f"Error fetching catalog: {e}")
        exit(1)

def get_season_from_timestamp(timestamp):
    month = int(timestamp.split('-')[1])
    return "warm" if 4 <= month <= 9 else "cold"

def process_apartment(apartment, publisher, adaptor):
    apartment_id = apartment['apartmentId']
    settings = apartment.get('settings')  # Apartment-specific settings
    print(f"\nProcessing Apartment: {apartment_id}")

    for room in apartment['rooms']:
        room_id = room['roomId']
        print(f"  -> Processing Room: {room_id}")
        room_data = []

        for sensor_id in room['sensors']:
            sensor_data = adaptor.get_sensor_data(sensor_id)
            if sensor_data:
                room_data.append(sensor_data)

        if room_data:
            # Compute average values per room
            avg_temp = sum(d['temperature'] for d in room_data) / len(room_data)
            avg_humidity = sum(d['humidity'] for d in room_data) / len(room_data)
            avg_co2 = sum(d['co2'] for d in room_data) / len(room_data)
            avg_pm10 = sum(d.get('pm10', 0) for d in room_data) / len(room_data)
            avg_tvoc = sum(d.get('tvoc', 0) for d in room_data) / len(room_data)

            # Determine the season based on the first timestamp
            season = get_season_from_timestamp(room_data[0]['timestamp'])

            # Adaptive Thermal Comfort calculation
            outdoor_temps = [d.get('outdoor_temp', avg_temp) for d in room_data][-7:]
            adaptive_comfort = adaptive_thermal_comfort(outdoor_temps)

            t_ext = adaptive_comfort['Running Mean Temperature'] if adaptive_comfort else avg_temp

            # Get adaptive temperature category from settings (default to 2 = Cat II)
            cat_num = settings["base_settings"]["thresholds"].get("adaptive_temp_category", 2)
            cat_label = f"Cat {'I' if cat_num == 1 else 'II' if cat_num == 2 else 'III'}"

            adaptive_range = None
            if adaptive_comfort:
                adaptive_range = adaptive_comfort["Acceptable Range"].get(cat_label)

            temp_class = classify_temperature(avg_temp, season, t_ext, settings, adaptive_range)

            # Base classifications
            hum_class = classify_humidity(avg_humidity, settings)
            co2_class = classify_co2(avg_co2, settings)

            # Advanced KPIs
            pmv = calculate_pmv(season, avg_temp, avg_temp, 0.1, avg_humidity, settings)
            pmv_class = classify_pmv(pmv, settings)

            ppd = calculate_ppd(pmv)
            ppd_class = classify_ppd(ppd, settings)

            icone = calculate_icone(avg_co2, avg_pm10, avg_tvoc)
            icone_class = classify_icone(icone, settings)

            ieqi = calculate_ieqi(icone, avg_temp, avg_humidity, settings)
            ieqi_class = classify_ieqi(ieqi, settings)

            # Overall environment score
            classifications = {
                "temperature": temp_class,
                "humidity": hum_class,
                "co2": co2_class,
                "pmv": pmv_class,
                "ppd": ppd_class,
                "icone": icone_class,
                "ieqi": ieqi_class
            }

            env_score = overall_score(classifications, settings)
            env_classification = classify_overall_score(env_score, settings)

            publish_room_metrics(
                                    publisher, apartment_id, room_id,
                                    avg_temp, avg_humidity, avg_co2,
                                    pmv, ppd, icone, ieqi,
                                    temp_class, hum_class, co2_class,
                                    pmv_class, ppd_class, icone_class, ieqi_class,
                                    adaptive_comfort, env_score, env_classification
                                )

def publish_room_metrics(publisher, apartment_id, room_id, avg_temp, avg_humidity, avg_co2,
                         pmv, ppd, icone, ieqi, temp_class, hum_class, co2_class,
                         pmv_class, ppd_class, icone_class, ieqi_class,
                         adaptive_comfort, env_score, env_classification):

    topic = f"{MQTT_BASE_TOPIC}/{apartment_id}/{room_id}/metrics"
    base_name = topic
    timestamp = time.time()  # Current Unix timestamp for all entries

    # Build SenML event list
    events = [
        {"n": "temperature", "v": avg_temp, "t": timestamp},
        {"n": "temperature_class", "vs": temp_class, "t": timestamp},

        {"n": "humidity", "v": avg_humidity, "t": timestamp},
        {"n": "humidity_class", "vs": hum_class, "t": timestamp},

        {"n": "co2", "v": avg_co2, "t": timestamp},
        {"n": "co2_class", "vs": co2_class, "t": timestamp},

        {"n": "pmv", "v": pmv, "t": timestamp},
        {"n": "pmv_class", "vs": pmv_class, "t": timestamp},

        {"n": "ppd", "v": ppd, "t": timestamp},
        {"n": "ppd_class", "vs": ppd_class, "t": timestamp},

        {"n": "icone", "v": icone, "t": timestamp},
        {"n": "icone_class", "vs": icone_class, "t": timestamp},

        {"n": "ieqi", "v": ieqi, "t": timestamp},
        {"n": "ieqi_class", "vs": ieqi_class, "t": timestamp},

        {"n": "environment_score", "v": env_score, "t": timestamp},
        {"n": "environment_score_class", "vs": env_classification, "t": timestamp}
    ]

    # Add adaptive comfort metrics, if available
    if adaptive_comfort:
        events.append({"n": "adaptive_comfort_running_mean", "v": adaptive_comfort.get("Running Mean Temperature", -999), "t": timestamp})
        events.append({"n": "adaptive_comfort_t_comf", "v": adaptive_comfort.get("Comfort Temperature", -999), "t": timestamp})

    # Build full SenML payload
    senml_payload = {
        "bn": base_name,
        "e": events
    }

    print(f"      Final SenML Metrics for {room_id}: {json.dumps(senml_payload, indent=2)}")
    print(f"Publishing on topic: {topic}")

    # Publish the message
    publisher.myPublish(json.dumps(senml_payload), topic)

def main():
    catalog = get_catalog()
    publisher = MyPublisher("KPIModule", "test_topic")
    publisher.start()
    adaptor = Adaptor()

    for apartment in catalog['apartments']:
        process_apartment(apartment, publisher, adaptor)

    publisher.stop()

if __name__ == "__main__":
    main()
