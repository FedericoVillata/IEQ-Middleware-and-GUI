import requests
from datetime import datetime, timedelta
import pandas as pd
import json
import time
import paho.mqtt.client as PahoMQTT

def get_users():
    users_url = "http://registry:8081/users"
    response = requests.get(users_url)
    if response.status_code != 200:
        raise Exception(f"Failed to fetch users data: {response.status_code}")
    return response.json()

def get_apartments():
    apartments_url = "http://registry:8081/apartments"
    response = requests.get(apartments_url)
    if response.status_code != 200:
        raise Exception(f"Failed to fetch apartments data: {response.status_code}")
    return response.json()

def process_netatmo_data(apartment_data):
    for mac_entry in apartment_data['MAC']:
        if mac_entry['name'] == "netatmo":
            mac_address = mac_entry['MAC']
            access_token = mac_entry['accessToken']
            refresh_token = mac_entry['refreshToken']
            sensors = {room['roomId']: room['sensors'][0] for room in apartment_data['rooms']}
            return mac_address, access_token, refresh_token, sensors
    raise Exception("No MAC entry with name 'netatmo' found.")

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

    def get_measurements(self, apartment_id, user_id):
        if self.first_request:
            last_data_url = f"http://adaptor:8080/getLastData/{user_id}/{apartment_id}/"
            print(f"Username: {user_id}, Apartment ID: {apartment_id}")
            print(f"Fetching last data from: {last_data_url}")  # Debug
            try:
                last_data_response = requests.get(last_data_url)
                if last_data_response.status_code == 200:
                    last_data = last_data_response.json()
                    last_timestamps = [
                        int(datetime.strptime(item["t"], "%m/%d/%Y, %H:%M:%S").timestamp())
                        for item in last_data
                    ]
                    if last_timestamps:
                        date_start = datetime.fromtimestamp(max(last_timestamps))  # Convert to datetime
                        print(f"Last data timestamp: {date_start}")
                    else:
                        print("No previous data found. Defaulting to the last 24 hours.")
                        date_start = datetime.now() - timedelta(days=1)
                elif last_data_response.status_code == 400:
                    print("Bad Request: Please check the parameters sent to the server.")
                    print(f"URL: {last_data_url}")
                    print(f"Response: {last_data_response.text}")
                    return
                else:
                    print(f"Failed to fetch last data: {last_data_response.status_code}")
                    return
            except Exception as e:
                print(f"Error fetching last data: {e}")
                return

            self.first_request = False
        else:
            date_start = datetime.now() - timedelta(minutes=30)
        
        # Convert `date_start` to a timestamp
        date_start = int(date_start.timestamp())
        date_end = int(datetime.now().timestamp())

        myPub = MyPublisher("54234")
        myPub.start()
        for module_name, module_id in self.modules.items():
            print(f"Getting measurements for {apartment_id}...")
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

            for data_type in ['Temperature', 'Humidity', 'CO2', 'Pressure', 'Noise']:
                Event = []
                for i, val in enumerate(values[data_type]):
                    event = {
                        "n": f"{data_type}/{module_name}/{module_id}",
                        "u": "Celsius" if data_type == "Temperature" else "Percentage" if data_type == "Humidity" else "ppm" if data_type == "CO2" else "hPa" if data_type == "Pressure" else "dB",
                        "t": str(values['timestamp'][i]),
                        "v": float(val) if val is not None else 0
                    }
                    Event.append(event)
                pubTopic = f"IEQmidAndGUI/{apartment_id}/{data_type}"
                out = {"bn": pubTopic, "e": Event}
                print(out)
                myPub.myPublish(json.dumps(out), pubTopic)
                time.sleep(1)

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
    apartments = get_apartments()
    for apartment in apartments:
        try:
            mac_address, access_token, refresh_token, sensors = process_netatmo_data(apartment)
            apartment_id = apartment['apartmentId']
            apartment_users = [
            user for user in users if apartment_id in user.get('apartments', [])
            ]

            for user in apartment_users:  # Itera sugli utenti associati all'appartamento
                user_id = user['userId']
                netatmo = NetatmoAPI(
                    clientId=config['client_id'],
                    clientSecret=config['client_secret'],
                    username=config['email'],
                    password=config['password'],
                    accessToken=access_token,
                    mac=mac_address,
                    modules=sensors,
                    scope='read_station'
                )
                while True:
                    netatmo.get_measurements(apartment_id,user_id)
                    time.sleep(1800)  # Attendi 30 minuti prima della prossima richiesta
        except Exception as e:
            print(f"Error processing apartment {apartment.get('apartmentId', 'unknown')}: {e}")
            continue