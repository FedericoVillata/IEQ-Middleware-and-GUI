# main_engine.py
import time
import json
from publisher_service import MyPublisher
from apartment_processor import process_apartment
from weather_service import get_external_weather
from data_fetcher import get_catalog
import requests, os

from datetime import datetime

def log(message, level="INFO", context=None):
    timestamp = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    prefix = f"[{timestamp}] [{level}]"
    # prefix = f"[{level}]"
    if context:
        prefix += f" [{context}]"
    print(f"{prefix} {message}")



class KPIEngine:

    def __init__(self):
        log("Initializing KPIEngine...")
        with open(os.path.join(os.path.dirname(__file__), 'config.json')) as f:
            self.config = json.load(f)

        self.ADAPTOR_BASE = self.config["adaptor_url"]
        self.REGISTRY_URL = self.config["registry_url"]
        self.MQTT_BASE_TOPIC = self.config["base_topic"]
        self.MQTT_BROKER = self.config.get("messageBroker")
        self.MQTT_PORT = self.config.get("brokerPort")
        self.MQTT_QOS = self.config.get("qos")

        self.publisher = MyPublisher("KPIModule", self.MQTT_BASE_TOPIC, self.MQTT_BROKER, self.MQTT_PORT, self.MQTT_QOS)
        self.catalog = get_catalog(self.REGISTRY_URL)

    def run(self):
        self.publisher.start()

        if "apartments" not in self.catalog or not isinstance(self.catalog["apartments"], list):
            raise ValueError("Catalog JSON missing or invalid: no 'apartments' list found.")

        for apartment in self.catalog.get("apartments", []):
            coords = apartment.get("coordinates", {})
            lat = coords.get("lat")
            lon = coords.get("long")

            if lat is None or lon is None:
                log("No coordinates found, skipping weather fetch", level="WARN", context=apartment.get("apartmentId"))
                continue

            weather_info = get_external_weather(lat, lon)
            process_apartment(
                apartment,
                self.catalog,
                weather_info,
                self.publisher,
                self.MQTT_BASE_TOPIC,
                self.ADAPTOR_BASE, 
                self.catalog.get("base_settings")
            )
        self.publisher.stop()
        log("KPI cycle completed successfully")


def wait_for_data(config_path='config.json'):
    try:
        with open(config_path) as f:
            config = json.load(f)
        adaptor_url = config["adaptor_url"]
        url = f"{adaptor_url}/getApartmentData/user0/apartment0?measurement=Temperature&duration=1"
    except Exception as e:
        log(f"Failed to load adaptor URL from config: {e}", level="ERROR")
        return

    while True:
        try:
            response = requests.get(url)
            if response.status_code == 200:
                data = response.json()
                if len(data) > 0:
                    log("Data received from adaptor.")
                    return
                else:
                    log("No data yet, retrying...", level="DEBUG")
            else:
                log(f"Unexpected status code: {response.status_code}", level="WARN")
        except Exception as e:
            log(f"Error contacting adaptor: {e}", level="ERROR")
        time.sleep(3)        


if __name__ == "__main__":
    log("Script started")

     # wait_for_data()  # Commented out for debug purposes

    INTERVAL_SECONDS = 10 * 60

    while True:
        log("Starting new KPI cycle...")
        try:
            engine = KPIEngine()
            engine.run()
        except Exception as e:
            log(f"Error during KPI cycle: {e}", level="ERROR")

        log(f"Waiting {INTERVAL_SECONDS / 60} minutes before next cycle...")
        time.sleep(INTERVAL_SECONDS)
