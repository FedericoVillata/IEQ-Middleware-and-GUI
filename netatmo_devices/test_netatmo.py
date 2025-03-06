import requests
from datetime import datetime, timedelta
import pandas as pd
import json
import matplotlib.pyplot as plt
import numpy as np
import time
from os import getenv
from os.path import expanduser
from pathlib import Path
import paho.mqtt.client as PahoMQTT
import time
from queue import Queue
import json



"""class ClientAuth:
    
    Request authentication and keep access token available through token method. Renew it automatically if necessary

    Args:
        clientId (str): Application clientId delivered by Netatmo on dev.netatmo.com
        clientSecret (str): Application Secret key delivered by Netatmo on dev.netatmo.com
        username (str): Netatmo account username
        password (str): Netatmo account password
    

    def __init__(self, clientId=None, clientSecret=None, username=None, password=None, scope='read_station', credentialFile=None):
        clientId = getenv("CLIENT_ID", clientId)
        clientSecret = getenv("CLIENT_SECRET", clientSecret)
        username = getenv("USERNAME", username)
        password = getenv("PASSWORD", password)

        if not (clientId and clientSecret and username and password):
            self._credentialFile = credentialFile or expanduser("./netatmo_config.json")
            with open(self._credentialFile, "r", encoding="utf-8") as f:
                cred = {k.upper(): v for k, v in json.loads(f.read()).items()}
        else:
            self._credentialFile = None

        self._clientId = clientId or cred["CLIENT_ID"]
        self._clientSecret = clientSecret or cred["CLIENT_SECRET"]
        self._accessToken = None
        self.username = username or cred["USERNAME"]
        self.password = password or cred["PASSWORD"]
        self.scope = scope
        self.expiration = 0

        self.manual_refresh()

    @property
    def accessToken(self):
        if self.expiration < time.time():
            self.manual_refresh()
        return self._accessToken

    def manual_refresh(self):
        postParams = {
            "grant_type": "password",
            "username": self.username,
            "password": self.password,
            "client_id": self._clientId,
            "client_secret": self._clientSecret,
            "scope": self.scope
        }
        response = requests.post("https://api.netatmo.com/oauth2/token", data=postParams)
        resp = response.json()

        if 'access_token' not in resp:
            print(f"Error refreshing token manually: {resp}")
            return

        self._accessToken = resp['access_token']
        self.expiration = int(resp['expire_in'] + time.time())

        cred = {
            "CLIENT_ID": self._clientId,
            "CLIENT_SECRET": self._clientSecret,
            "USERNAME": self.username,
            "PASSWORD": self.password
        }
        if self._credentialFile:
            with open(self._credentialFile, "w", encoding="utf-8") as f:
                f.write(json.dumps(cred, indent=True))"""


class NetatmoAPI:
    def __init__(self, clientId, clientSecret, username, password,accessToken, mac, modules, scope='read_station'):
        self.clientId = clientId
        self.clientSecret = clientSecret
        self.username = username
        self.password = password
        self.mac = mac
        self.modules = modules
        self.scope = scope
        self.base_url = 'https://api.netatmo.com'
        self.data = {module: None for module in modules}
        self._accessToken = accessToken
        self.expiration = 0
        self.manual_refresh()
        self.first_request = True

    @property
    def accessToken(self):
        if self.expiration >= time.time():
            self.manual_refresh()
        return self._accessToken

    def manual_refresh(self):
        postParams = {
            "grant_type": "password",
            "username": self.username,
            "password": self.password,
            "client_id": self.clientId,
            "client_secret": self.clientSecret,
            "scope": self.scope
        }
        response = requests.post("https://api.netatmo.com/oauth2/token", data=postParams)
        resp = response.json()

        if 'access_token' not in resp:
            print(f"Error refreshing token manually: {resp}")
            return

        self._accessToken = resp['access_token']
        self.expiration = int(resp['expire_in'] + time.time())

    def get_measurements(self):
        """if self.first_request:
            date_start = datetime.now() - timedelta(days=1)
            self.first_request = False
        else:
            date_start = datetime.now() - timedelta(minutes=30)"""
        date_start = datetime.now() - timedelta(minutes=30)
        
        date_start = int(date_start.replace(tzinfo=None).timestamp())
        date_end = int(datetime.now().timestamp())

        myPub = MyPublisher("54234")
        myPub.start()
        for module_name, module_id in self.modules.items():
            pubTopic = f"IEQmidAndGUI/apartment_1/{module_name}/Temperature"
            url = f'{self.base_url}/api/getmeasure'
            params = {
                'device_id': self.mac,
                'module_id': module_id,
                'scale': '30min',
                'type': 'Temperature,Humidity,CO2,Pressure,Noise',
                'date_begin': date_start,
                'date_end': date_end,
                'limit': '1024',
                'optimize': 'true',
                'real_time': 'true'
            }
            headers = {
                "accept": "application/json",
                "Authorization": f"Bearer {self.accessToken}"
            }

            response = requests.get(url=url, params=params, headers=headers)

            if response.status_code != 200:
                print(f"Error: {response.status_code}")
                print(response.content)
                continue

            try:
                body = response.json()['body'][0]
            except (KeyError, IndexError, json.JSONDecodeError) as e:
                print(f"Error parsing response: {e}")
                print(response.content)
                continue

            values = {
                'Temperature': [val[0] for val in body['value']],
                'Humidity': [val[1] for val in body['value']],
                'CO2': [val[2] for val in body['value']],
                'Pressure': [val[3] for val in body['value']],
                'Noise': [val[4] for val in body['value']]
            }

            datetime_start = datetime.fromtimestamp(body['beg_time'])
            step_time = body.get('step_time', 1)

            values['timestamp'] = [datetime_start + timedelta(seconds=i * step_time) for i in range(len(values['Temperature']))]

            self.data[module_name] = pd.DataFrame.from_dict(values)
            self.data[module_name] = self.data[module_name].set_index('timestamp')
            print(f"Data for {module_name}:")
            print(self.data[module_name].head())
            Event =[]
            """event = {"n": "Temperature", "u": "Celsius", "t": str(time.time()), "v": 30}#VolumetricWaterContent
                out = {"bn": pubTopic,"e":[event]}"""
            i = 0
            for val in values['Temperature']:
                event = {"n": "Temperature", "u": "Celsius", "t": str(values['timestamp'][i]), "v": float(val)}
                Event.append(event)
                i += 1
            out = {"bn": pubTopic,"e":Event}
            print(out)
            
            myPub.myPublish(json.dumps(out), pubTopic)
            myPub.stop()
            time.sleep(12)
            """json_data = {
                "module_name": module_name,
                "measurements": self.data[module_name].to_dict(orient='records')
            }
            # Print data in JSON format
            print(json.dumps(json_data, indent=4))"""

    def plot_measurements(self):
        plt.figure(figsize=(12, 10))
        for i, (module_name, df) in enumerate(self.data.items(), 1):
            if df is not None:
                plt.subplot(len(self.data), 1, i)
                plt.plot(df['humidity'], label='Humidity')
                plt.plot(df['temperature'], label='Temperature')
                plt.title(f'{module_name} Measurements')
                plt.grid()
                plt.legend()
        plt.tight_layout()
        plt.show()

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
    
    with open('./netatmo_config.json') as config_file:
        config = json.load(config_file)

    
    modules = {
        'stanza_1': config['mac'],  # Main module
        'stanza_2': '03:00:00:0c:e0:b2',      # Internal module 1
        'stanza_3': '03:00:00:0c:e0:98',      # Internal module 2
        'stanza_4': '03:00:00:0d:34:20',      # Internal module 3
        'esterno': '02:00:00:af:60:ee'        # External module
    }

    
    netatmo = NetatmoAPI(
        clientId=config['client_id'],
        clientSecret=config['client_secret'],
        username=config['email'],
        password=config['password'],
        accessToken=config['access_token'],
        mac=config['mac'],
        modules=modules,
        scope='read_station'
    )

    while True:
        netatmo.get_measurements()
        time.sleep(1800)  # Wait for 30 min before the next request