import random
import time

class Adaptor:
    def get_sensor_data(self, sensor_id):
        return {
            "sensor_id": sensor_id,
            "timestamp": time.strftime("%Y-%m-%d-%H:%M:%S"),
            "temperature": round(random.uniform(20, 26), 2),
            "humidity": round(random.uniform(40, 60), 2),
            "co2": random.randint(600, 1500),
            "pm10": round(random.uniform(10, 40), 2),
            "tvoc": round(random.uniform(0.1, 0.4), 2),
            "outdoor_temp": round(random.uniform(15, 30), 2)
        }
