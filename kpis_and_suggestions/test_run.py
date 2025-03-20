# test_run.py
import json
from main import process_apartment


# Mock Publisher
class MockPublisher:
    def myPublish(self, msg, topic):
        print(f"\n[MOCK PUBLISH] Topic: {topic}")
        print(f"[MOCK PAYLOAD] {msg}\n")

    def start(self):
        print("[MOCK PUBLISHER STARTED]")

    def stop(self):
        print("[MOCK PUBLISHER STOPPED]")

# Mock Adaptor
class MockAdaptor:
    def get_sensor_data(self, sensor_id):
        # Return static values for testing
        return {
            "sensorId": sensor_id,
            "timestamp": "2024-05-15-12:00",
            "temperature": 22.5,
            "humidity": 45,
            "co2": 800,
            "pm10": 30,
            "tvoc": 0.2,
            "outdoor_temp": 18.0
        }

if __name__ == "__main__":
    # Carico il catalog locale dalla json
    with open("catalog.json") as f:
        catalog = json.load(f)

    publisher = MockPublisher()
    publisher.start()

    adaptor = MockAdaptor()

    # Testa solo l'appartamento di Luca
    for apartment in catalog['apartments']:
        if apartment['apartmentId'] == 'apartment1':
            process_apartment(apartment, publisher, adaptor)

    publisher.stop()
