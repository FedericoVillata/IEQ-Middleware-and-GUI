from datetime import datetime, timedelta
import requests
import json
from os import getenv
from os.path import expanduser
from pathlib import Path
import paho.mqtt.client as PahoMQTT
import time
from queue import Queue
import json
import time
import warnings



class CapettiAPI:
    def __init__(self, username, rest_license, mac):
        self.username = username
        self.rest_license = rest_license
        self.mac = mac
        self.base_url = 'https://www.winecap.it/api/v1/'
        self.token = None
        self.first_request = True

    def get_user_token(self):
        url = f'{self.base_url}?action=getUserToken&Login={self.username}&RESTLicense={self.rest_license}'
        headers = {
            'Content-Type': 'application/json'
        }
        response = requests.post(url=url, headers=headers, verify=True)

        if response.status_code == 200:
            # Verifica che il token sia presente nella risposta
            self.token = response.json().get('UserToken')
            if self.token:
                print("User token retrieved successfully.")
            else:
                print("Error: Token not found in response.")
        else:
            print(f"Error retrieving user token: {response.status_code}")
            print("Response Content:", response.content)
    
    def get_sensor_list(self, first_request):
        if not self.token:
            print("Error: User token not available.")
            return

        url = f'{self.base_url}?action=getSensorList'
        params = {
            'wliMac': self.mac
        }
        headers = {
            'Content-Type': 'application/json',
            'Authorization': f"Bearer {self.token}"
        }
        response = requests.get(url=url, params=params, headers=headers, verify=False)

        if response.status_code != 200:
            print(f"Error: {response.status_code}")
            print(response.content)
            return

        try:
            data = response.json()
        except (json.JSONDecodeError) as e:
            print(f"Error parsing response: {e}")
            print(response.content)
            return
        
        for item in data:
            #print(item)
            if item['sensorMac'] == '0000E795':
                if first_request:
                    self.get_history_values(sensor_mac=item['sensorMac'], sensor_ch=1)
                else:
                    self.get_current_values()
                


    def get_history_values(self, sensor_mac, sensor_ch):
        if not self.token:
            print("Error: User token not available.")
            return

        date_to = int(time.time())  
        date_from = date_to - 24 * 3600  #  24 hours

        url = f'{self.base_url}?action=getChannelHistory'
        params = {
            'wliMac': self.mac,
            'sensorMac': sensor_mac,
            'sensorCh': sensor_ch,
            'dateFrom': date_from,
            'dateTo': date_to
        }
        headers = {
            'Content-Type': 'application/json',
            'Authorization': f"Bearer {self.token}"
        }

        response = requests.get(url=url, params=params, headers=headers, verify=False)

        if response.status_code != 200:
            print(f"Error: {response.status_code}")
            print(response.content)
            return

        try:
            data = response.json()
        except (json.JSONDecodeError) as e:
            print(f"Error parsing response: {e}")
            print(response.content)
            return

        pubTopic = f"IEQmidAndGUI/user1-apartment1/0000E795/Temperature"
        #myPub = MyPublisher("54234")
        #myPub.start()
        for item in data:
            event = {
                "n": "Temperature",
                "u": "Celsius",
                "t": str(datetime.utcfromtimestamp(int(item['timeStamp']))),
                "v": float(item['value'])
            }
            out = {"bn": pubTopic, "e": [event]}
            print(out)
            #myPub.myPublish(json.dumps(out), pubTopic)
            #myPub.stop()
            time.sleep(0.1)
        

    def get_current_values(self):
        pubTopic = f"IEQmidAndGUI/user1-apartment1/0000E795/Temperature"
        if not self.token:
            print("Error: User token not available.")
            return

        url = f'{self.base_url}?action=getCurrentValues'
        params = {
            'wliMac': self.mac
        }
        headers = {
            'Content-Type': 'application/json',
            'Authorization': f"Bearer {self.token}"
        }

        response = requests.get(url=url, params=params, headers=headers, verify=False)

        if response.status_code != 200:
            print(f"Error: {response.status_code}")
            print(response.content)
            return

        try:
            data = response.json()
        except (json.JSONDecodeError) as e:
            print(f"Error parsing response: {e}")
            print(response.content)
            return

        values = {
            'sensorName': [],
            'sensorMac': [],
            'channel': [],
            'channelType': [],
            'timestamp': [],
            'value': [],
            'invalid': [],
            'alarm': []
        }
        sensor = {
            'name': [],
            'channel': [],
            'timestamp': [],
            'type': [],
            'value': [],
            'unit': []
        }
        #myPub = MyPublisher("54234")
        #myPub.start()
        for item in data:
            if item['sensorMac'] == '0000E795':  
                values['sensorName'].append(item['sensorName'])
                values['sensorMac'].append(item['sensorMac'])
                values['channel'].append(item['channel'])
                values['channelType'].append(item['channelType'])
                values['timestamp'].append(datetime.utcfromtimestamp(int(item['timeStamp'])))
                values['value'].append(item['value'])
                values['invalid'].append(item['invalid'])
                values['alarm'].append(item['alarm'])

                if item['channel'] == '1':
                    event = {
                            "n": "Temperature",
                            "u": "Celsius",
                            "t": str(datetime.utcfromtimestamp(int(item['timeStamp']))),
                            "v": float(item['value'])
                        }
                    out = {"bn": pubTopic, "e": [event]}
                    print(out)
                    #myPub.myPublish(json.dumps(out), pubTopic)
                    #myPub.stop()
        #print(sensor)

class MyPublisher:
    def __init__(self, clientID):
        self.clientID = clientID  + "Temperature"
    
        # create an instance of paho.mqtt.client
        self._paho_mqtt = PahoMQTT.Client(self.clientID, False) 
        # register the callback
        self._paho_mqtt.on_connect = self.myOnConnect
        try:
            with open("settings.json", "r") as fs:                
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

    with open('./config_capetti.json') as config_file:
        config = json.load(config_file)

    capetti = CapettiAPI(
        username=config['username'],
        rest_license=config['rest_license'],
        mac=config['mac']
    )
    
    capetti.get_user_token()

    while True:
        """if capetti.first_request:
            capetti.get_history_values(sensor_mac='0000E795', sensor_ch=1)
            capetti.first_request = False
        else:
            capetti.get_current_values()"""
        capetti.get_sensor_list(capetti.first_request)
        capetti.first_request = False
        time.sleep(600) # 10 minutes  