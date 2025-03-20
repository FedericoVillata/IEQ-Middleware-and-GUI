import sys
import os
sys.path.append(os.path.abspath(os.path.join(os.path.dirname(__file__), '..')))


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
    ventilation = apartment.get('ventilation', 'nat')
    print(f"\nProcessing Apartment: {apartment_id} with ventilation: {ventilation}")

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
            temp_class = classify_temperature(avg_temp, season, ventilation, t_ext)

            # Base classifications
            hum_class = classify_humidity(avg_humidity)
            co2_class = classify_co2(avg_co2, ventilation)

            # Advanced KPIs
            pmv = calculate_pmv(season, avg_temp, avg_temp, 0.1, avg_humidity)
            pmv_class = classify_pmv(pmv)

            ppd = calculate_ppd(pmv)
            ppd_class = classify_ppd(ppd)

            icone = calculate_icone(avg_co2, avg_pm10, avg_tvoc)
            icone_class = classify_icone(icone)

            ieqi = calculate_ieqi(icone, avg_temp, avg_humidity)
            ieqi_class = classify_ieqi(ieqi)

            # Compute the overall environment score
            env_score = compute_environment_score(
                temp_class, hum_class, co2_class, pmv_class, ppd_class, ieqi_class, icone_class
            )
            env_classification = classify_environment_score(env_score)

            # Prepare final payload
            metrics_payload = {
                "temperature": {"value": avg_temp, "classification": temp_class},
                "humidity": {"value": avg_humidity, "classification": hum_class},
                "co2": {"value": avg_co2, "classification": co2_class},
                "pmv": {"value": pmv, "classification": pmv_class},
                "ppd": {"value": ppd, "classification": ppd_class},
                "icone": {"value": icone, "classification": icone_class},
                "ieqi": {"value": ieqi, "classification": ieqi_class},
                "adaptive_comfort": adaptive_comfort,
                "environment_score": {
                    "score_percent": env_score,
                    "classification": env_classification
                }
            }

            print(f"      Final Metrics for {room_id}: {json.dumps(metrics_payload, indent=2)}")

            topic = f"{MQTT_BASE_TOPIC}/{apartment_id}/{room_id}/metrics"
            print(f"Publishing on topic: {topic}")
            publisher.myPublish(json.dumps(metrics_payload), topic)

        else:
            print(f"      No valid data to compute metrics for {room_id}")

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
