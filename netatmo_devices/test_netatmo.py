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



def get_users():
    users_url = "http://localhost:8081/users"
    response = requests.get(users_url)
    if response.status_code != 200:
        raise Exception(f"Failed to fetch users data: {response.status_code}")
    return response.json()

def get_apartments():
    apartments_url = "http://localhost:8081/apartments"
    response = requests.get(apartments_url)
    if response.status_code != 200:
        raise Exception(f"Failed to fetch apartments data: {response.status_code}")
    return response.json()

def get_user_data(users, user_id):
    for user in users:
        if user['userId'] == user_id:
            return user
    raise Exception(f"User {user_id} not found in registry")

def get_apartment_data(apartments, user_id):
    for apartment in apartments:
        if user_id in apartment['users']:
            print("apt: ", apartment)
            return apartment
    raise Exception(f"Apartment for user {user_id} not found in registry")

class NetatmoAPI:
    def __init__(self, clientId, clientSecret, username, password, accessToken, mac, modules, scope='read_station'):
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
        if self.first_request:
            date_start = datetime.now() - timedelta(days=1)
            self.first_request = False
        else:
            date_start = datetime.now() - timedelta(minutes=30)
        
        date_start = int(date_start.replace(tzinfo=None).timestamp())
        date_end = int(datetime.now().timestamp())

        myPub = MyPublisher("54234")
        myPub.start()
        for module_name, module_id in self.modules.items():
            print(f"Getting measurements for {apartment_id}...")
            pubTopic = f"IEQmidAndGUI/{apartment_id}"
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

            values['timestamp'] = [(datetime_start + timedelta(seconds=i * step_time)).timestamp() for i in range(len(values['Temperature']))]
            self.data[module_name] = pd.DataFrame.from_dict(values)
            self.data[module_name] = self.data[module_name].set_index('timestamp')
            print(f"Data for {module_name}:")
            print(self.data[module_name].head())
            Event = []
            i = 0
            for val in values['Temperature']:
                event = {"n": f"Temperature/{module_name}/{module_id}", "u": "Celsius", "t": str(values['timestamp'][i]), "v": float(val)}
                Event.append(event)
                i += 1
            out = {"bn": pubTopic, "e": Event}
            print(out)
            myPub.myPublish(json.dumps(out), pubTopic)
            time.sleep(1)

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
        self.clientID = clientID + "Temperature"
        self._paho_mqtt = PahoMQTT.Client(self.clientID, False)
        self._paho_mqtt.on_connect = self.myOnConnect
        try:
            with open("settings.json", "r") as fs:
                self.settings = json.loads(fs.read())
        except Exception:
            print("Problem in loading settings")
        self.messageBroker = self.settings["messageBroker"]
        self.port = self.settings["brokerPort"]
        self.qos = self.settings["qos"]

    def start(self):
        self._paho_mqtt.connect(self.messageBroker, self.port)
        self._paho_mqtt.loop_start()

    def stop(self):
        self._paho_mqtt.loop_stop()
        self._paho_mqtt.disconnect()

    def myPublish(self, message, topic):
        self._paho_mqtt.publish(topic, message, self.qos)

    def myOnConnect(self, paho_mqtt, userdata, flags, rc):
        print("Connected to %s with result code: %d" % (self.messageBroker, rc))

if __name__ == '__main__':

    with open('./netatmo_config.json') as config_file:
        config = json.load(config_file)
    users = get_users()
    user_data = get_user_data(users, "Luca1")
    apartments = get_apartments()
    apartment_data = get_apartment_data(apartments, "Luca1")

    mac_data = apartment_data['MAC'][0]
    sensors = {room['roomId']: room['sensors'][0] for room in apartment_data['rooms']}
    apartment_id = apartment_data['apartmentId']

    netatmo = NetatmoAPI(
        clientId=config['client_id'],
        clientSecret=config['client_secret'],
        username=config['email'],
        password=config['password'],
        accessToken=mac_data['accessToken'], #accessToken="67251bc704bee2bc3e05de23|29340711a8de4a6917e8a54d93fdfa29"
        mac=mac_data['MAC'],
        modules=sensors,
        scope='read_station'
    )

    while True:
        netatmo.get_measurements()
        time.sleep(1800)  # Wait for 30 min before the next request