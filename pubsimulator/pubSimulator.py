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
        self.clientID = clientID  + "Temperature"
        self.topic = topic
		# create an instance of paho.mqtt.client
        self._paho_mqtt = PahoMQTT.Client(self.clientID, False) 
		# register the callback
        self._paho_mqtt.on_connect = self.myOnConnect
        try:
            with open(SETTINGS, "r") as fs:                
                self.settings = json.loads(fs.read())            
        except Exception:
            print("Problem in loading settings")
        self.messageBroker = self.settings["messageBroker"]
        self.port = self.settings["brokerPort"]
        self.qos = self.settings["qos"]

    def start (self):
		#manage connection to broker
        self._paho_mqtt.connect(self.messageBroker, self.port)
        self._paho_mqtt.loop_start()

    def stop (self):
        self._paho_mqtt.loop_stop()
        self._paho_mqtt.disconnect()

    def myPublish(self, message, topic):
		# publish a message with a certain topic
        self._paho_mqtt.publish(topic, message, self.qos)

    def myOnConnect (self, paho_mqtt, userdata, flags, rc):
        print ("Connected to %s with result code: %d" % (self.messageBroker, rc))


if __name__ == '__main__':

    pubTopic = "IEQmidAndGUI/apartment0"
    pubTopic2 = "IEQmidAndGUI/apartment0"
    print(pubTopic)
    myPub = MyPublisher("54234", pubTopic)
    myPub.start()
    while True:              
        event = {"n": "Temperature/room0/sensor0", "u": "Celsius", "t": str(time.time()), "v": 30}#VolumetricWaterContent
        out = {"bn": pubTopic,"e":[event]}
        print(out)
        myPub.myPublish(json.dumps(out), pubTopic)
        event = {"n": "Temperature/room1/sensor1", "u": "Celsius", "t": str(time.time()), "v": 34}#VolumetricWaterContent
        out = {"bn": pubTopic2,"e":[event]}
        myPub.myPublish(json.dumps(out), pubTopic2)
            
        time.sleep(10)