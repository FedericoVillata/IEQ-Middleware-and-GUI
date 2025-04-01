# import sys
# import os
# sys.path.append(os.path.abspath(os.path.join(os.path.dirname(__file__), '..')))

# import time
# import json
# import requests
# from adaptor.adaptor import *
# from kpis_classification import *
# from pubsimulator.publisher import MyPublisher

# REGISTRY_URL = 'http://localhost:8080/catalog'
# MQTT_BASE_TOPIC = 'home'

# ADAPTOR_BASE = "http://adaptor:8080"

# def fetch_data(userId, apartmentId, measure, start=None, end=None, duration=None):
#     """
#     If 'start' and 'end' are provided => calls /getDatainPeriod
#     else if 'duration' => calls /getApartmentData
#     else => defaults to 168 hours
#     """
#     if start and end:
#         # date range approach
#         adaptor_url = f"{self.ADAPTOR_BASE}/getDatainPeriod/{userId}/{apartmentId}"
#         params = {
#             "measurament": measure,
#             "start": f"{start}T00:00:00Z",
#             "stop":  f"{end}T23:59:59Z",
#         }
#         print("DEBUG: calling getDatainPeriod =>", adaptor_url, params)
#     else:
#         # fallback to duration approach
#         dur = duration if duration else "168"
#         adaptor_url = f"{self.ADAPTOR_BASE}/getApartmentData/{userId}/{apartmentId}"
#         params = {
#             "measurament": measure,
#             "duration": dur,
#         }
#         print("DEBUG: calling getApartmentData =>", adaptor_url, params)

#     results = []
#     try:
#         resp = requests.get(adaptor_url, params=params, timeout=10)
#         print("DEBUG: adaptor response =>", resp.status_code)
#         if resp.status_code == 200:
#             results = resp.json()
#             print("DEBUG: parsed JSON =>", len(results), "records")
#         else:
#             print("ERROR: adaptor returned status", resp.status_code)
#     except Exception as exc:
#         print("ERROR in _fetch_data:", exc)
#     return results

# #def get_catalog():
#  #   try:
#   #      response = requests.get(REGISTRY_URL)
#    #     response.raise_for_status()
#     #    return response.json()
#     #except requests.RequestException as e:
#     #    print(f"Error fetching catalog: {e}")
#      #   exit(1)

# def get_catalog():
#     with open("catalog.json") as f:
#         return json.load(f)
    

# def get_season_from_timestamp(timestamp):
#     month = int(timestamp.split('-')[1])
#     return "warm" if 4 <= month <= 9 else "cold"

# # def process_apartment(apartment, publisher, adaptor):
# #     apartment_id = apartment['apartmentId']
# #     settings = apartment.get('settings')  # Apartment-specific settings
# #     print(f"\nProcessing Apartment: {apartment_id}")

# #     for room in apartment['rooms']:
# #         room_id = room['roomId']
# #         print(f"  -> Processing Room: {room_id}")
# #         room_data = []

# #         for sensor_id in room['sensors']:
# #             sensor_data = adaptor.get_sensor_data(sensor_id)
# #             if sensor_data:
# #                 room_data.append(sensor_data)

# #         if room_data:
# #             # Compute average values per room
# #             avg_temp = sum(d['temperature'] for d in room_data) / len(room_data)
# #             avg_humidity = sum(d['humidity'] for d in room_data) / len(room_data)
# #             avg_co2 = sum(d['co2'] for d in room_data) / len(room_data)
# #             avg_pm10 = sum(d.get('pm10', 0) for d in room_data) / len(room_data)
# #             avg_tvoc = sum(d.get('tvoc', 0) for d in room_data) / len(room_data)

# #             # Determine the season based on the first timestamp
# #             season = get_season_from_timestamp(room_data[0]['timestamp'])

# #             # Adaptive Thermal Comfort calculation
# #             outdoor_temps = [d.get('outdoor_temp', avg_temp) for d in room_data][-7:]
# #             adaptive_comfort = adaptive_thermal_comfort(outdoor_temps)

# #             t_ext = adaptive_comfort['Running Mean Temperature'] if adaptive_comfort else avg_temp

# #             # Get adaptive temperature category from settings (default to 2 = Cat II)
# #             cat_num = settings["base_settings"]["thresholds"].get("adaptive_temp_category", 2)
# #             cat_label = f"Cat {'I' if cat_num == 1 else 'II' if cat_num == 2 else 'III'}"

# #             adaptive_range = None
# #             if adaptive_comfort:
# #                 adaptive_range = adaptive_comfort["Acceptable Range"].get(cat_label)

# #             temp_class = classify_temperature(avg_temp, season, t_ext, settings, adaptive_range)

# #             # Base classifications
# #             hum_class = classify_humidity(avg_humidity, settings)
# #             co2_class = classify_co2(avg_co2, settings)

# #             # Advanced KPIs
# #             pmv = calculate_pmv(season, avg_temp, avg_temp, 0.1, avg_humidity, settings)
# #             pmv_class = classify_pmv(pmv, settings)

# #             ppd = calculate_ppd(pmv)
# #             ppd_class = classify_ppd(ppd, settings)

# #             icone = calculate_icone(avg_co2, avg_pm10, avg_tvoc)
# #             icone_class = classify_icone(icone, settings)

# #             ieqi = calculate_ieqi(icone, avg_temp, avg_humidity, settings)
# #             ieqi_class = classify_ieqi(ieqi, settings)

# #             # Overall environment score
# #             classifications = {
# #                 "temperature": temp_class,
# #                 "humidity": hum_class,
# #                 "co2": co2_class,
# #                 "pmv": pmv_class,
# #                 "ppd": ppd_class,
# #                 "icone": icone_class,
# #                 "ieqi": ieqi_class
# #             }

# #             env_score = overall_score(classifications, settings)
# #             env_classification = classify_overall_score(env_score, settings)

# #             publish_room_metrics(
# #                                     publisher, apartment_id, room_id,
# #                                     avg_temp, avg_humidity, avg_co2,
# #                                     pmv, ppd, icone, ieqi,
# #                                     temp_class, hum_class, co2_class,
# #                                     pmv_class, ppd_class, icone_class, ieqi_class,
# #                                     adaptive_comfort, env_score, env_classification
# #                                 )


# def process_apartment(apartment, publisher, adaptor):
#     apartment_id = apartment['apartmentId']
#     print(f"\nProcessing Apartment: {apartment_id}")

#     # Load full catalog to fall back on default settings
#     catalog = get_catalog()

#     # Use apartment-specific settings if present, otherwise default to catalog's base_settings
#     settings = apartment.get("settings", catalog["base_settings"])

#     for room in apartment['rooms']:
#         room_id = room['roomId']
#         print(f"  -> Processing Room: {room_id}")

#         # Use the first user assigned to the apartment for data access
#         userId = apartment["users"][0]

#         # Define the required environmental measures
#         measures = ["Temperature", "Humidity", "CO2", "PM10", "TVOC"]
#         measure_data = {}

#         # Fetch each measure via the REST adaptor using fetch_data()
#         for measure in measures:
#             fetched = fetch_data(userId, apartment_id, measure, duration="168")
#             if not fetched:
#                 continue
#             # Filter only values that belong to the current room
#             room_filtered = [entry for entry in fetched if entry.get("room") == room_id]
#             measure_data[measure] = room_filtered

#         # Proceed only if the essential metrics are present
#         if all(measure_data.get(m) for m in ["Temperature", "Humidity", "CO2"]):
#             avg_temp = np.mean([d["value"] for d in measure_data["Temperature"]])
#             avg_humidity = np.mean([d["value"] for d in measure_data["Humidity"]])
#             avg_co2 = np.mean([d["value"] for d in measure_data["CO2"]])
#             avg_pm10 = np.mean([d["value"] for d in measure_data.get("PM10", [])]) if measure_data.get("PM10") else 0
#             avg_tvoc = np.mean([d["value"] for d in measure_data.get("TVOC", [])]) if measure_data.get("TVOC") else 0

#             # Determine the season based on the first timestamp available
#             season = get_season_from_timestamp(measure_data["Temperature"][0]["timestamp"])

#             # Compute adaptive comfort metrics if available
#             outdoor_temps = [d.get("outdoor_temp", avg_temp) for d in measure_data["Temperature"]][-7:]
#             adaptive_comfort = adaptive_thermal_comfort(outdoor_temps)
#             t_ext = adaptive_comfort['Running Mean Temperature'] if adaptive_comfort else avg_temp

#             # Determine the adaptive temperature category range
#             cat_num = settings["thresholds"].get("adaptive_temp_category", 2)
#             cat_label = f"Cat {'I' if cat_num == 1 else 'II' if cat_num == 2 else 'III'}"
#             adaptive_range = adaptive_comfort["Acceptable Range"].get(cat_label) if adaptive_comfort else None

#             # Basic KPI classification
#             temp_class = classify_temperature(avg_temp, season, t_ext, settings, adaptive_range)
#             hum_class = classify_humidity(avg_humidity, settings)
#             co2_class = classify_co2(avg_co2, settings)

#             # Advanced KPIs
#             pmv = calculate_pmv(season, avg_temp, avg_temp, 0.1, avg_humidity, settings)
#             pmv_class = classify_pmv(pmv, settings)

#             ppd = calculate_ppd(pmv)
#             ppd_class = classify_ppd(ppd, settings)

#             icone = calculate_icone(avg_co2, avg_pm10, avg_tvoc)
#             icone_class = classify_icone(icone, settings)

#             ieqi = calculate_ieqi(icone, avg_temp, avg_humidity, settings)
#             ieqi_class = classify_ieqi(ieqi, settings)

#             # Calculate overall environmental score
#             classifications = {
#                 "temperature": temp_class,
#                 "humidity": hum_class,
#                 "co2": co2_class,
#                 "pmv": pmv_class,
#                 "ppd": ppd_class,
#                 "icone": icone_class,
#                 "ieqi": ieqi_class
#             }

#             env_score = overall_score(classifications, settings)
#             env_classification = classify_overall_score(env_score, settings)

#             # Publish the metrics via MQTT
#             publish_room_metrics(
#                 publisher, apartment_id, room_id,
#                 avg_temp, avg_humidity, avg_co2,
#                 pmv, ppd, icone, ieqi,
#                 temp_class, hum_class, co2_class,
#                 pmv_class, ppd_class, icone_class, ieqi_class,
#                 adaptive_comfort, env_score, env_classification
#             )



# def publish_room_metrics(publisher, apartment_id, room_id, avg_temp, avg_humidity, avg_co2,
#                          pmv, ppd, icone, ieqi, temp_class, hum_class, co2_class,
#                          pmv_class, ppd_class, icone_class, ieqi_class,
#                          adaptive_comfort, env_score, env_classification):

#     topic = f"{MQTT_BASE_TOPIC}/{apartment_id}/{room_id}/metrics"
#     base_name = topic
#     timestamp = time.time()  # Current Unix timestamp for all entries

#     # Build SenML event list
#     events = [
#         {"n": "temperature", "v": avg_temp, "t": timestamp},
#         {"n": "temperature_class", "vs": temp_class, "t": timestamp},

#         {"n": "humidity", "v": avg_humidity, "t": timestamp},
#         {"n": "humidity_class", "vs": hum_class, "t": timestamp},

#         {"n": "co2", "v": avg_co2, "t": timestamp},
#         {"n": "co2_class", "vs": co2_class, "t": timestamp},

#         {"n": "pmv", "v": pmv, "t": timestamp},
#         {"n": "pmv_class", "vs": pmv_class, "t": timestamp},

#         {"n": "ppd", "v": ppd, "t": timestamp},
#         {"n": "ppd_class", "vs": ppd_class, "t": timestamp},

#         {"n": "icone", "v": icone, "t": timestamp},
#         {"n": "icone_class", "vs": icone_class, "t": timestamp},

#         {"n": "ieqi", "v": ieqi, "t": timestamp},
#         {"n": "ieqi_class", "vs": ieqi_class, "t": timestamp},

#         {"n": "environment_score", "v": env_score, "t": timestamp},
#         {"n": "environment_score_class", "vs": env_classification, "t": timestamp}
#     ]

#     # Add adaptive comfort metrics, if available
#     if adaptive_comfort:
#         events.append({"n": "adaptive_comfort_running_mean", "v": adaptive_comfort.get("Running Mean Temperature", -999), "t": timestamp})
#         events.append({"n": "adaptive_comfort_t_comf", "v": adaptive_comfort.get("Comfort Temperature", -999), "t": timestamp})

#     # Build full SenML payload
#     senml_payload = {
#         "bn": base_name,
#         "e": events
#     }

#     print(f"      Final SenML Metrics for {room_id}: {json.dumps(senml_payload, indent=2)}")
#     print(f"Publishing on topic: {topic}")

#     # Publish the message
#     publisher.myPublish(json.dumps(senml_payload), topic)

# def main():
#     catalog = get_catalog()
#     publisher = MyPublisher("KPIModule", "test_topic")
#     publisher.start()
#     adaptor = Adaptor()

#     for apartment in catalog['apartments']:
#         process_apartment(apartment, publisher, adaptor)

#     publisher.stop()

# if __name__ == "__main__":
#     main()

import sys
import os
sys.path.append(os.path.abspath(os.path.join(os.path.dirname(__file__), '..')))

import time
import json
import requests
import numpy as np

from adaptor.adaptor import Adaptor
from kpis_classification import *
from pubsimulator.publisher import MyPublisher


class KPIEngine:
    # Constants for registry and MQTT
    ADAPTOR_BASE = "http://adaptor:8080"
    REGISTRY_URL = 'http://localhost:8080/catalog'
    MQTT_BASE_TOPIC = 'home'

    def __init__(self):
        # Load catalog, initialize publisher and adaptor
        self.catalog = self.get_catalog()
        self.publisher = MyPublisher("KPIModule", "test_topic")
        self.adaptor = Adaptor()

    def get_catalog(self):
        # Load catalog from local file
        with open("catalog.json") as f:
            return json.load(f)

    def get_season_from_timestamp(self, timestamp):
        # Extract season from timestamp (cold or warm)
        month = int(timestamp.split('-')[1])
        return "warm" if 4 <= month <= 9 else "cold"

    def fetch_data(self, userId, apartmentId, measure, start=None, end=None, duration=None):
        # Call the appropriate adaptor endpoint based on time range or duration
        if start and end:
            url = f"{self.ADAPTOR_BASE}/getDatainPeriod/{userId}/{apartmentId}"
            params = {
                "measurament": measure,
                "start": f"{start}T00:00:00Z",
                "stop": f"{end}T23:59:59Z",
            }
        else:
            dur = duration if duration else "168"
            url = f"{self.ADAPTOR_BASE}/getApartmentData/{userId}/{apartmentId}"
            params = {
                "measurament": measure,
                "duration": dur,
            }

        try:
            resp = requests.get(url, params=params, timeout=10)
            if resp.status_code == 200:
                return resp.json()
            else:
                print("ERROR: adaptor returned", resp.status_code)
        except Exception as e:
            print("ERROR in fetch_data:", e)

        return []

    def process_apartment(self, apartment):
        apartment_id = apartment['apartmentId']
        print(f"\nProcessing Apartment: {apartment_id}")

        # Use apartment-specific settings if available, otherwise fallback to global
        settings = apartment.get("settings", self.catalog["base_settings"])

        for room in apartment['rooms']:
            room_id = room['roomId']
            print(f"  -> Processing Room: {room_id}")

            userId = apartment["users"][0]
            measures = ["Temperature", "Humidity", "CO2", "PM10", "TVOC"]
            measure_data = {}

            # Fetch and filter measurements by room
            for measure in measures:
                fetched = self.fetch_data(userId, apartment_id, measure, duration="168")
                if not fetched:
                    continue
                room_filtered = [e for e in fetched if e.get("room") == room_id]
                measure_data[measure] = room_filtered

            # Proceed if essential metrics are available
            if all(measure_data.get(m) for m in ["Temperature", "Humidity", "CO2"]):
                avg_temp = np.mean([d["value"] for d in measure_data["Temperature"]])
                avg_humidity = np.mean([d["value"] for d in measure_data["Humidity"]])
                avg_co2 = np.mean([d["value"] for d in measure_data["CO2"]])
                avg_pm10 = np.mean([d["value"] for d in measure_data.get("PM10", [])]) if measure_data.get("PM10") else 0
                avg_tvoc = np.mean([d["value"] for d in measure_data.get("TVOC", [])]) if measure_data.get("TVOC") else 0

                season = self.get_season_from_timestamp(measure_data["Temperature"][0]["timestamp"])
                outdoor_temps = [d.get("outdoor_temp", avg_temp) for d in measure_data["Temperature"]][-7:]
                adaptive_comfort = adaptive_thermal_comfort(outdoor_temps)
                t_ext = adaptive_comfort['Running Mean Temperature'] if adaptive_comfort else avg_temp

                cat_num = settings["thresholds"].get("adaptive_temp_category", 2)
                cat_label = f"Cat {'I' if cat_num == 1 else 'II' if cat_num == 2 else 'III'}"
                adaptive_range = adaptive_comfort["Acceptable Range"].get(cat_label) if adaptive_comfort else None

                # Classify metrics
                temp_class = classify_temperature(avg_temp, season, t_ext, settings, adaptive_range)
                hum_class = classify_humidity(avg_humidity, settings)
                co2_class = classify_co2(avg_co2, settings)
                pmv = calculate_pmv(season, avg_temp, avg_temp, 0.1, avg_humidity, settings)
                pmv_class = classify_pmv(pmv, settings)
                ppd = calculate_ppd(pmv)
                ppd_class = classify_ppd(ppd, settings)
                icone = calculate_icone(avg_co2, avg_pm10, avg_tvoc)
                icone_class = classify_icone(icone, settings)
                ieqi = calculate_ieqi(icone, avg_temp, avg_humidity, settings)
                ieqi_class = classify_ieqi(ieqi, settings)

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

                self.publish_room_metrics(
                    apartment_id, room_id,
                    avg_temp, avg_humidity, avg_co2,
                    pmv, ppd, icone, ieqi,
                    temp_class, hum_class, co2_class,
                    pmv_class, ppd_class, icone_class, ieqi_class,
                    adaptive_comfort, env_score, env_classification
                )

    def publish_room_metrics(self, apartment_id, room_id, avg_temp, avg_humidity, avg_co2,
                             pmv, ppd, icone, ieqi, temp_class, hum_class, co2_class,
                             pmv_class, ppd_class, icone_class, ieqi_class,
                             adaptive_comfort, env_score, env_classification):

        topic = f"{self.MQTT_BASE_TOPIC}/{apartment_id}/{room_id}/metrics"
        base_name = topic
        timestamp = time.time()

        # Build list of SenML entries
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

        if adaptive_comfort:
            events.append({"n": "adaptive_comfort_running_mean", "v": adaptive_comfort.get("Running Mean Temperature", -999), "t": timestamp})
            events.append({"n": "adaptive_comfort_t_comf", "v": adaptive_comfort.get("Comfort Temperature", -999), "t": timestamp})

        senml_payload = {"bn": base_name, "e": events}

        print(f"      Final SenML Metrics for {room_id}: {json.dumps(senml_payload, indent=2)}")
        print(f"Publishing on topic: {topic}")
        self.publisher.myPublish(json.dumps(senml_payload), topic)

    def run(self):
        # Start publisher and process all apartments
        self.publisher.start()
        for apartment in self.catalog['apartments']:
            self.process_apartment(apartment)
        self.publisher.stop()


if __name__ == "__main__":
    engine = KPIEngine()
    engine.run()
