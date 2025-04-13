import sys
import os
sys.path.append(os.path.abspath(os.path.join(os.path.dirname(__file__), '..')))

import time
import json
import requests
import numpy as np

from kpis_classification import *
from kpis_and_suggestions.tenant_suggestions import *
from kpis_and_suggestions.technical_suggestions import *
from publisher import MyPublisher
from datetime import datetime

print("kpis_engine.py started")

# Fetch weather data from Open-Meteo API
def get_external_weather():
    try:
        url = "https://api.open-meteo.com/v1/forecast?latitude=45.08&longitude=7.68&hourly=temperature_2m,weather_code&timezone=auto&forecast_days=1"
        response = requests.get(url)
        if response.status_code != 200:
            raise Exception(f"Bad response: {response.status_code}")

        data = response.json()
        now_hour = datetime.now().hour
        temp_now = data["hourly"]["temperature_2m"][now_hour]
        code_now = data["hourly"]["weather_code"][now_hour]

        sunny = code_now == 0
        temp_list = data["hourly"]["temperature_2m"][:now_hour+1]
        temp_drop = len(temp_list) >= 2 and temp_list[-1] < temp_list[0]

        bad_weather_codes = {61, 63, 65, 80, 81, 82}
        bad_days = sum(1 for c in data["hourly"]["weather_code"] if c in bad_weather_codes)

        return {
            "temperature": temp_now,
            "weather_code": code_now,
            "sunny": sunny,
            "temp_drop": temp_drop,
            "bad_days": bad_days
        }
    except Exception as e:
        print(f"Weather fetch failed: {e}")
        return {
            "temperature": -999,
            "weather_code": -1,
            "sunny": False,
            "temp_drop": False,
            "bad_days": 0
        }

class KPIEngine:

    def __init__(self):
        print("Initializing KPIEngine...")
        with open(os.path.join(os.path.dirname(__file__), 'config.json')) as f:
            self.config = json.load(f)

        try:
            self.ADAPTOR_BASE = self.config["adaptor_url"]
            self.REGISTRY_URL = self.config["registry_url"]
            self.MQTT_BASE_TOPIC = self.config["base_topic"]
            self.MQTT_BROKER = self.config.get("messageBroker")
            self.MQTT_PORT = self.config.get("brokerPort")
            self.MQTT_QOS = self.config.get("qos")
        except KeyError as e:
            raise ValueError(f"Missing configuration key: {e}")

        self.catalog = self.get_catalog()
        if "apartments" not in self.catalog or not isinstance(self.catalog["apartments"], list):
            raise ValueError("Catalog JSON missing or invalid: no 'apartments' list found.")

        self.publisher = MyPublisher("KPIModule", self.MQTT_BASE_TOPIC, self.MQTT_BROKER, self.MQTT_PORT, self.MQTT_QOS)

    def get_catalog(self, retries=10, delay=3):
        for attempt in range(retries):
            try:
                response = requests.get(self.REGISTRY_URL + "/catalog")
                response.raise_for_status()
                print("Catalog fetched successfully.")
                return response.json()
            except requests.RequestException as e:
                print(f"[Attempt {attempt + 1}] Error fetching catalog: {e}")
                time.sleep(delay)
        print("Failed to fetch catalog after several retries. Exiting.")
        exit(1)

    def fetch_data(self, userId, apartmentId, measure, start=None, end=None, duration=None, retries=3, delay=2):
        if start and end:
            url = f"{self.ADAPTOR_BASE}/getDatainPeriod/{userId}/{apartmentId}"
            params = {
                "measurement": measure,
                "start": f"{start}T00:00:00Z",
                "stop": f"{end}T23:59:59Z",
            }
        else:
            dur = duration if duration else "168"
            url = f"{self.ADAPTOR_BASE}/getApartmentData/{userId}/{apartmentId}"
            params = {
                "measurement": measure,
                "duration": dur,
            }

        for attempt in range(retries):
            try:
                print(f"[Attempt {attempt+1}] Fetching {measure} data from: {url} with params: {params}")
                resp = requests.get(url, params=params, timeout=10)
                if resp.status_code == 200:
                    data = resp.json()
                    print(f"Fetched {len(data)} items for {measure}")
                    return data
                else:
                    print(f"ERROR: adaptor returned {resp.status_code}")
            except Exception as e:
                print(f"ERROR in fetch_data (attempt {attempt+1}): {e}")
            time.sleep(delay)

        print(f"Failed to fetch {measure} after {retries} attempts.")
        return []
    
    def fetch_feedback(self, user_id, apartment_id, room_id, duration=168):
        try:
            url = f"{self.ADAPTOR_BASE}/getRoomData/{user_id}/{apartment_id}/{room_id}?measurement=feedback&duration={duration}"
            response = requests.get(url)
            if response.status_code == 200:
                raw_data = response.json()
                
                # Organizza per tipo di feedback, assumendo che 'v' sia una stringa tipo "thermal_comfort:complaint"
                feedback_dict = {}
                for entry in raw_data:
                    if "v" in entry and isinstance(entry["v"], str) and ":" in entry["v"]:
                        category, value = entry["v"].split(":", 1)
                        feedback_dict.setdefault(category.strip(), []).append({"type": value.strip(), "time": entry.get("t")})
                return feedback_dict
            else:
                print(f"[Feedback] Unexpected status code: {response.status_code}")
        except Exception as e:
            print(f"[Feedback] Error fetching feedback: {e}")
        return {}

    
    def process_apartment(self, apartment, weather_info):
        apartment_id = apartment['apartmentId']
        print(f"\nProcessing Apartment: {apartment_id}")

        base_settings = apartment.get("settings", self.catalog["base_settings"])
        season = "warm" if 4 <= datetime.now().month <= 9 else "cold"

        for room in apartment['rooms']:
            room_id = room['roomId']
            print(f"  Processing Room: {room_id}")

            userId = apartment["users"][0]
            measures = ["Temperature", "Humidity", "CO2", "PM10", "VOC"]
            measure_data = {}

            for measure in measures:
                fetched = self.fetch_data(userId, apartment_id, measure, duration="168")
                if not fetched:
                    print(f"No data fetched for {measure}")
                    continue
                room_filtered = [e for e in fetched if e.get("room") == room_id]
                measure_data[measure] = room_filtered

            required_metrics = ["Temperature", "Humidity", "CO2"]
            missing = [m for m in required_metrics if not measure_data.get(m)]

            if missing:
                print(f"Missing data for {room_id} in {apartment_id}: {missing}")
                alert_event = {
                    "bn": f"{self.MQTT_BASE_TOPIC}/{apartment_id}",
                    "e": [{
                        "n": f"missing_data/{room_id}",
                        "t": time.time(),
                        "u": "error",
                        "v": f"Missing data: {', '.join(missing)}"
                    }]
                }
                self.publisher.myPublish(json.dumps(alert_event), f"{self.MQTT_BASE_TOPIC}/{apartment_id}")
                continue

            # Optional metrics
            optional_missing = [m for m in ["PM10", "VOC"] if not measure_data.get(m)]
            if optional_missing:
                print(f"Optional data missing in {room_id}: {optional_missing}")
                warning_event = {
                    "bn": f"{self.MQTT_BASE_TOPIC}/{apartment_id}",
                    "e": [{
                        "n": f"missing_optional_data/{room_id}",
                        "t": time.time(),
                        "u": "warning",
                        "v": f"Optional data missing: {', '.join(optional_missing)}"
                    }]
                }
                self.publisher.myPublish(json.dumps(warning_event), f"{self.MQTT_BASE_TOPIC}/{apartment_id}")

            # Calculate averages
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

            outdoor_temps = [d.get("outdoor_temp", avg_temp) for d in measure_data["Temperature"]][-7:]
            adaptive_comfort = adaptive_thermal_comfort(outdoor_temps)
            t_ext = adaptive_comfort['Running Mean Temperature'] if adaptive_comfort else avg_temp
            cat_num = base_settings["thresholds"].get("adaptive_temp_category", 2)
            cat_label = f"Cat {'I' if cat_num == 1 else 'II' if cat_num == 2 else 'III'}"
            adaptive_range = adaptive_comfort["Acceptable Range"].get(cat_label) if adaptive_comfort else None

            if adaptive_range is None:
                print(f"Missing adaptive range for {cat_label}, skipping room.")
                continue

            # Classifications
            temp_class = classify_temperature(avg_temp, season, t_ext, base_settings, adaptive_range)
            hum_class = classify_humidity(avg_humidity, base_settings)
            co2_class = classify_co2(avg_co2, base_settings)
            pmv = calculate_pmv(season, avg_temp, avg_temp, 0.1, avg_humidity, base_settings)
            pmv_class = classify_pmv(pmv, base_settings)
            ppd = calculate_ppd(pmv)
            ppd_class = classify_ppd(ppd, base_settings)

            classifications = {
                "temperature": temp_class,
                "humidity": hum_class,
                "co2": co2_class,
                "pmv": pmv_class,
                "ppd": ppd_class
            }

            icone = None
            ieqi = None
            icone_class = None
            ieqi_class = None

            if avg_pm10 is not None and avg_tvoc is not None:
                icone = calculate_icone(avg_co2, avg_pm10, avg_tvoc)
                icone_class = classify_icone(icone, base_settings)
                ieqi = calculate_ieqi(icone, avg_temp, avg_humidity, base_settings)
                ieqi_class = classify_ieqi(ieqi, base_settings)

                classifications["icone"] = icone_class
                classifications["ieqi"] = ieqi_class

            env_score = overall_score(classifications, base_settings)
            env_classification = classify_overall_score(env_score, base_settings)
            classifications["overall_score"] = env_classification

            self.publish_room_metrics(
                apartment_id, room_id,
                avg_temp, avg_humidity, avg_co2,
                pmv, ppd, icone, ieqi,
                temp_class, hum_class, co2_class,
                pmv_class, ppd_class, icone_class, ieqi_class,
                adaptive_comfort, env_score, env_classification
            )

            # Alerts
            critical_labels = ["R", "Extreme", "Very Cold", "Very Warm"]
            for metric, label in classifications.items():
                if label in critical_labels:
                    alert_event = {
                        "bn": f"{self.MQTT_BASE_TOPIC}/{apartment_id}",
                        "e": [{
                            "n": f"alert/{room_id}",
                            "t": time.time(),
                            "u": "alert",
                            "v": f"{metric} classified as {label}"
                        }]
                    }
                    self.publisher.myPublish(json.dumps(alert_event), f"{self.MQTT_BASE_TOPIC}/{apartment_id}")

            # Prepare context for suggestions
            context_values = dict(base_settings.get("values", {}))
            context_values.update({
                "season": season,
                "weather": "rain" if weather_info.get("weather_code") in {61, 63, 65, 80, 81, 82} else "clear",
                "forecast": {
                    "sun": weather_info.get("sunny", False),
                    "bad_days": weather_info.get("bad_days", 0),
                    "temp_drop": weather_info.get("temp_drop", False)
                }
            })
            suggestion_settings = dict(base_settings)
            suggestion_settings["values"] = context_values

            # Tenant suggestions
            tenant_suggestions = get_tenant_suggestions(
                classifications=classifications,
                temp=avg_temp,
                humidity=avg_humidity,
                co2=avg_co2,
                t_ext=t_ext,
                hour=datetime.now().hour,
                pmv=pmv,
                trends=trends,
                settings=suggestion_settings
            )

            if tenant_suggestions:
                print(f"Generated {len(tenant_suggestions)} suggestions for room {room_id}")

            self.publish_tenant_suggestions(apartment_id, room_id, tenant_suggestions)

            # Technical suggestions
            feedback_data = self.fetch_feedback(userId, apartment_id, room_id)

            technical_suggestions = get_technical_suggestions(
                classifications=classifications,
                feedback=feedback_data,
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
                    "overall_score": env_score
                },
                settings=suggestion_settings
            )

            self.publish_technical_suggestions(apartment_id, room_id, technical_suggestions)


    def publish_room_metrics(self, apartment_id, room_id, avg_temp, avg_humidity, avg_co2,
                            pmv, ppd, icone, ieqi, temp_class, hum_class, co2_class,
                            pmv_class, ppd_class, icone_class, ieqi_class,
                            adaptive_comfort, env_score, env_classification):

        topic = f"{self.MQTT_BASE_TOPIC}/{apartment_id}"
        base_name = topic
        timestamp = time.time()

        events = [
            {"n": f"avg_temperature/{room_id}/value", "u": "Cel", "t": timestamp, "v": avg_temp},
            {"n": f"temperature_class/{room_id}/class", "u": "class", "t": timestamp, "v": temp_class},
            {"n": f"avg_humidity/{room_id}/value", "u": "%RH", "t": timestamp, "v": avg_humidity},
            {"n": f"humidity_class/{room_id}/class", "u": "class", "t": timestamp, "v": hum_class},
            {"n": f"avg_co2/{room_id}/value", "u": "ppm", "t": timestamp, "v": avg_co2},
            {"n": f"co2_class/{room_id}/class", "u": "class", "t": timestamp, "v": co2_class},
            {"n": f"pmv_kpis/{room_id}/value", "u": "arb", "t": timestamp, "v": pmv},
            {"n": f"pmv_class/{room_id}/class", "u": "class", "t": timestamp, "v": pmv_class},
            {"n": f"ppd/{room_id}/value", "u": "%", "t": timestamp, "v": ppd},
            {"n": f"ppd_class/{room_id}/class", "u": "class", "t": timestamp, "v": ppd_class},
            {"n": f"icone/{room_id}/value", "u": "arb", "t": timestamp, "v": icone},
            {"n": f"icone_class/{room_id}/class", "u": "class", "t": timestamp, "v": icone_class},
            {"n": f"ieqi/{room_id}/value", "u": "arb", "t": timestamp, "v": ieqi},
            {"n": f"ieqi_class/{room_id}/class", "u": "class", "t": timestamp, "v": ieqi_class},
            {"n": f"environment_score/{room_id}/value", "u": "score", "t": timestamp, "v": env_score},
            {"n": f"environment_score_class/{room_id}/class", "u": "class", "t": timestamp, "v": env_classification}
        ]

        if adaptive_comfort:
            events.append({
                "n": f"adaptive_comfort_running_mean/{room_id}/value",
                "u": "value",
                "t": timestamp,
                "v": adaptive_comfort.get("Running Mean Temperature", -999)
            })
            events.append({
                "n": f"adaptive_comfort_t_comf/{room_id}/value",
                "u": "value",
                "t": timestamp,
                "v": adaptive_comfort.get("Comfort Temperature", -999)
            })

        for event in events:
            payload = {"bn": base_name, "e": [event]}
            print(f"\n🔁 Publishing event: {event['n']} to topic: {topic}")
            print(json.dumps(payload, indent=2))
            self.publisher.myPublish(json.dumps(payload), topic)

    def publish_tenant_suggestions(self, apartment_id, room_id, suggestions):
        if not suggestions:
            return

        topic = f"{self.MQTT_BASE_TOPIC}/{apartment_id}"
        timestamp = time.time()

        for metric, tip in suggestions.items():
            event = {
                "bn": topic,
                "e": [{
                    "n": f"tenant_suggestion/{room_id}/{metric}",
                    "t": timestamp,
                    "u": "string",
                    "v": tip
                }]
            }
            print(f"\n📌 Publishing suggestion for {metric} in {room_id}: {tip}")
            self.publisher.myPublish(json.dumps(event), topic)

    def publish_technical_suggestions(self, apartment_id, room_id, suggestions):
        if not suggestions:
            return

        topic = f"{self.MQTT_BASE_TOPIC}/{apartment_id}"
        timestamp = time.time()

        for key, tip in suggestions.items():
            event = {
                "bn": topic,
                "e": [{
                    "n": f"technical_suggestion/{room_id}/{key}",
                    "t": timestamp,
                    "u": "string",
                    "v": tip
                }]
            }
            print(f"\n🛠️ Publishing technical suggestion for {key} in {room_id}: {tip}")
            self.publisher.myPublish(json.dumps(event), topic)

def wait_for_data(config_path='config.json'):
    try:
        with open(config_path) as f:
            config = json.load(f)
        adaptor_url = config["adaptor_url"]
        url = f"{adaptor_url}/getApartmentData/user0/apartment0?measurement=Temperature&duration=1"
    except Exception as e:
        print(f"Failed to load adaptor URL from config: {e}")
        return

    while True:
        try:
            response = requests.get(url)
            if response.status_code == 200:
                data = response.json()
                if len(data) > 0:
                    print("Data received from adaptor.")
                    return
                else:
                    print("No data yet, retrying...")
            else:
                print(f"Unexpected status code: {response.status_code}")
        except Exception as e:
            print("Error contacting adaptor:", e)
        time.sleep(3)

if __name__ == "__main__":
    print("Script started")

    # wait_for_data()  # Commented out for debug purposes

    INTERVAL_SECONDS = 30 * 60

    while True:
        print("Starting new KPI cycle...")
        try:
            engine = KPIEngine()
            engine.run()
        except Exception as e:
            print(f"Error during KPI cycle: {e}")

        print(f"Waiting {INTERVAL_SECONDS / 60} minutes before next cycle...\n")
        time.sleep(INTERVAL_SECONDS)
