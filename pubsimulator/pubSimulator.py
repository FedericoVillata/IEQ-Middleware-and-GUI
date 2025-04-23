from pathlib import Path
import paho.mqtt.client as PahoMQTT
import time
from queue import Queue
import json
import requests
from requests.exceptions import HTTPError

P = Path(__file__).parent.absolute()
SETTINGS = P / 'settings.json'

def get_request(url):
    """Make a request to the url specified with retries"""
    for i in range(15):
            try:
                response = requests.get(url)
                response.raise_for_status()
                return json.loads(response.text)
            except HTTPError as http_err:
                print(f"HTTP error occurred: {http_err}")
            except Exception as err:
                print(f"Other error occurred: {err}")
            time.sleep(1)
    return []

class MyPublisher:
    def __init__(self, clientID, topic):
        self.clientID = clientID + "Temperature"
        self.topic = topic
        self._paho_mqtt = PahoMQTT.Client(self.clientID, False)
        self._paho_mqtt.on_connect = self.myOnConnect
        self.messageBroker = "mqtt.eclipseprojects.io"
        self.port = 1883
        self.qos = 2
        self.connected = False  # Flag to track connection state

    def start(self, timeout=5):
        self._paho_mqtt.connect(self.messageBroker, self.port)
        self._paho_mqtt.loop_start()

        # Wait until connected or timeout
        waited = 0
        while not self.connected and waited < timeout:
            time.sleep(0.1)
            waited += 0.1

        if not self.connected:
            print("⚠️ MQTT client failed to connect within timeout.")

    def stop(self):
        self._paho_mqtt.loop_stop()
        self._paho_mqtt.disconnect()

    def myPublish(self, message, topic, retries=3, sleep_time=1):
        while not self.connected:
            print("Waiting for MQTT connection to restore...")
            time.sleep(0.2)

        attempts = 0
        # while attempts < retries:
        info = self._paho_mqtt.publish(topic, message, self.qos)

        if info.rc == PahoMQTT.MQTT_ERR_SUCCESS:

            print(f"✅ Message with topic {topic} published successfully")

        else:
            print(f"⚠️ Publish failed with error code: {info.rc}")

    def myOnConnect(self, paho_mqtt, userdata, flags, rc):
        if rc == 0:
            self.connected = True
            print(f"✅ Connected to {self.messageBroker}")
        else:
            print(f"❌ Connection failed with result code: {rc}")


if __name__ == '__main__':

    pubTopic = "IEQmidAndGUI/apartment0/sensorData"
    pubTopic2 = "IEQmidAndGUI/apartment0/sensorData"
    print(pubTopic)
    myPub = MyPublisher("542340032", pubTopic)
    myPub.start()
    while True:              
        event = {"n": "Temperature/room0/sensor0", "u": "Celsius", "t": str(time.time()), "v": 30}#VolumetricWaterContent
        out = {"bn": pubTopic,"e":[event]}
        print(out)
        myPub.myPublish(json.dumps(out), pubTopic)
        event = {"n": "Temperature/room1/sensor1", "u": "Celsius", "t": str(time.time()), "v": 34}#VolumetricWaterContent
        out = {"bn": pubTopic2,"e":[event]}
        myPub.myPublish(json.dumps(out), pubTopic2)

        timestamp= str(time.time())

        avg_temp = 23.5  # °C
        temp_class = "Comfortable"

        avg_humidity = 45.0  # %
        hum_class = "Optimal"

        avg_co2 = 650  # ppm
        co2_class = "Normal"

        pmv = 0.2  # Predicted Mean Vote, range: [-3, 3]
        pmv_class = "Neutral"

        ppd = 10  # Predicted Percentage Dissatisfied, in %
        ppd_class = "Low dissatisfaction"

        icone = 75  # Indoor Comfort Index, valore inventato
        icone_class = "Good"

        ieqi = 85  # Indoor Environmental Quality Index
        ieqi_class = "Excellent"

        env_score = 88  # Punteggio complessivo dell’ambiente
        env_classification = "Very Good"
        room_id = "room0"  # ID della stanza
        events = [
                {"n": f"temperature_kpis/{room_id}/value", "v": avg_temp, "t": timestamp, "u": "Value"},
                {"n": f"temperature_class/{room_id}/class", "v": temp_class, "t": timestamp, "u": "Classification"},
                {"n": f"humidity/{room_id}/value", "v": avg_humidity, "t": timestamp, "u": "Value"},
                {"n": f"humidity_class/{room_id}/class", "v": hum_class, "t": timestamp, "u": "Classification"},
                {"n": f"co2/{room_id}/value", "v": avg_co2, "t": timestamp, "u": "Value"}
            ]
        
        out = {"bn": pubTopic2,"e":events}
        #myPub.myPublish(json.dumps(out), pubTopic2)

        time.sleep(10)