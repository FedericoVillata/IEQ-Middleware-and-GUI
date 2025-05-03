import requests
from datetime import datetime, timedelta
import pandas as pd
import json
import time
import paho.mqtt.client as PahoMQTT

def get_apartments(registry_url):
    apartments_url = f"{registry_url}/apartments"
    response = requests.get(apartments_url)
    if response.status_code != 200:
        raise Exception(f"Failed to fetch apartments data: {response.status_code}")
    return response.json()

def process_netatmo_data(apartment_data):
    for mac_entry in apartment_data['MAC']:
        if mac_entry['name'] == "netatmo":
            mac_address = mac_entry['MAC']
            access_token = mac_entry['accessToken']
            print(f"Access token: {access_token}")
            refresh_token = mac_entry['refreshToken']
            sensors={}
            for room in apartment_data['rooms']:
                sen = []
                for sensor in room['sensors']:
                    sen.append(sensor['sensorId'])
                sensors[room['roomId']] = sen
                        
            return apartment_data['apartmentId'],mac_address, access_token, refresh_token, sensors
    raise Exception("No MAC entry with name 'netatmo' found.")
def get_data(firth_request, apartment_id, mac, access_token, modules):
    if firth_request:
        date_to = int(time.time())  # Timestamp current
        date_from = date_to - int(timedelta(days=30).total_seconds())  
        print(f"Fetching data for the last 24 hours from {datetime.fromtimestamp(date_from)} to {datetime.fromtimestamp(date_to)}")

        # one hour block
        current_start = date_from
        while current_start < date_to:
            current_end = current_start + int(timedelta(days=1).total_seconds())
            print(f"Fetching data from {datetime.fromtimestamp(current_start)} to {datetime.fromtimestamp(current_end)}")
            netatmo.get_measurements(apartment_id, mac, access_token, modules, current_start, current_end)
            current_start = current_end
            time.sleep(3)
    else:
        date_to = int(time.time())
        date_from = date_to - int(timedelta(minutes=30).total_seconds())
        print(f"Fetching data for the last 30 minutes from {datetime.fromtimestamp(date_from)} to {datetime.fromtimestamp(date_to)}")
        netatmo.get_measurements(apartment_id, mac, access_token, modules, date_from, date_to)

class NetatmoAPI:
    def __init__(self, clientId, clientSecret, username, password,netatmo_url, scope='read_station'):
        self.clientId = clientId
        self.clientSecret = clientSecret
        self.username = username
        self.password = password
        self.scope = scope
        self.base_url = netatmo_url
        self.expiration = 0
        self.refreshToken = None  
        self._accessToken = None
        self.registry_url = None  
        self.apartment_id = None
        #self.manual_refresh()
        self.first_request = True
        self.publisher = MyPublisher("NetatmoPublisher")

    def manual_refresh(self, registry_url, apartment_id):
        print("🔄 Refreshing Netatmo token...")
        url = f"{self.base_url.rstrip('/')}/oauth2/token"
        payload = {
            "grant_type": "refresh_token",
            "refresh_token": self.refreshToken,
            "client_id": self.clientId,
            "client_secret": self.clientSecret
        }
        headers = {
            "User-Agent": "netatmo-client/1.0"
        }

        response = requests.post(url, data=payload, headers=headers)
        try:
            data = response.json()
        except Exception:
            raise Exception("❌ Invalid response while refreshing token")

        if response.status_code == 200:
            self._accessToken = data["access_token"]
            self.refreshToken = data["refresh_token"]
            self.expiration = int(time.time()) + int(data["expires_in"])
            print("✅ Access token refreshed successfully (in locale).")
            self.update_tokens_in_registry(registry_url, apartment_id, self._accessToken, self.refreshToken)

            
        else:
            if "invalid_grant" in response.text:
                print("❌ Refresh token invalid. Attempting to obtain a new token...")
                self.obtain_new_refresh_token(registry_url, apartment_id)
            else:
                raise Exception(f"❌ Failed to refresh token: {data}")
    def obtain_new_refresh_token(self,registry_url, apartment_id):
        print("🔄 Obtaining a new refresh token...")
        url = f"{self.base_url.rstrip('/')}/oauth2/token"
        payload = {
            "grant_type": "password",
            "username": self.username,
            "password": self.password,
            "client_id": self.clientId,
            "client_secret": self.clientSecret,
            "scope": self.scope
        }
        headers = {
            "User-Agent": "netatmo-client/1.0"
        }

        retries = 3
        for attempt in range(retries):
            response = requests.post(url, data=payload, headers=headers)
            try:
                if response.headers.get("Content-Type", "").startswith("application/json"):
                    data = response.json()
                else:
                    print("❌ Invalid response format. Response content:")
                    print(response.text)
                    raise Exception("❌ Response is not in JSON format")
            except Exception as e:
                print(f"❌ Failed to parse response while obtaining new refresh token (Attempt {attempt + 1}/{retries}). Error:")
                print(e)
                if attempt < retries - 1:
                    print("🔄 Retrying...")
                    time.sleep(2 ** attempt)
                    continue
                else:
                    raise Exception("❌ Failed to obtain new refresh token after multiple attempts.")

            if response.status_code == 200:
                self._accessToken = data["access_token"]
                self.refreshToken = data["refresh_token"]
                self.expiration = int(time.time()) + int(data["expires_in"])
                print("✅ New refresh token obtained successfully.")
                
                # Save the new refresh token in the registry
                self.update_tokens_in_registry(registry_url, apartment_id, self._accessToken, self.refreshToken)

                return
            else:
                print("❌ Failed to obtain new refresh token. Response content:")
                print(data)
                if attempt < retries - 1:
                    print("🔄 Retrying...")
                    time.sleep(2 ** attempt)
                    continue
                else:
                    raise Exception(f"❌ Failed to obtain new refresh token: {data.get('error', 'Unknown error')}")

    def update_tokens_in_registry(self, registry_url, apartment_id, new_access_token, new_refresh_token):
        
        try:
        
            update_url = f"{registry_url}/apartments/{apartment_id}/update_tokens"
            payload = {
                "accessToken": new_access_token,
                "refreshToken": new_refresh_token
            }

            headers = {
                "Content-Type": "application/json",
                "User-Agent": "netatmo-client/1.0"
            }

            response = requests.put(update_url, json=payload, headers=headers)

            if response.status_code == 200:
                print(f"✅ Token updated succesfully for  {apartment_id}")
            else:
                print(f"❌ Error during the update of token for  {apartment_id}: {response.status_code}")
                print(response.text)

        except Exception as e:
            print(f"❌ Error during the update of token in registry: {e}")

    @property
    def accessToken(self):
        if self.expiration < time.time() + 1800:
            if not self.registry_url or not self.apartment_id:
                raise Exception("no registry.")
            self.manual_refresh(self.registry_url, self.apartment_id)
        return self._accessToken

    def get_measurements(self, apartment_id, mac, accessToken, modules,current_start, current_end):
        self.data = {module: None for module in modules}
        
        date_start = current_start
        date_end = current_end

        pubTopic = f"IEQmidAndGUI/{apartment_id}/sensorData"
        for module_name, module_id in modules.items():
            print(f"Getting measurements for {apartment_id}...")
            url = f'{self.base_url}/api/getmeasure'
            params = {
                'device_id': mac,
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
                "Authorization": f"Bearer {accessToken}"
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

            for data_type in ['Temperature', 'Humidity', 'CO2']:
                Event = []
                for i, val in enumerate(values[data_type]):
                    if isinstance(module_id, list) and len(module_id) == 1:
                        module_id = module_id[0]# take the module_id from the list
                    event = {
                        "n": f"{data_type}/{module_name}/{module_id}",
                        "u": "Celsius" if data_type == "Temperature" else "Percentage" if data_type == "Humidity" else "ppm" if data_type == "CO2" else "hPa" if data_type == "Pressure" else "dB",
                        "t": str(values['timestamp'][i]),
                        "v": float(val) if val is not None else 0
                    }
                    Event.append(event)
                
                out = {"bn": pubTopic, "e": Event}
                print(out)
                self.publisher.myPublish(json.dumps(out), pubTopic)
                time.sleep(1)  

class MyPublisher:
    def __init__(self, clientID):
        self.connected = False
        self.clientID = clientID 
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

    def myPublish(self, message, topic):
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
    with open('./netatmo_config.json') as config_file:
        config = json.load(config_file)
    netatmo = NetatmoAPI(
        clientId=config['client_id'],
        clientSecret=config['client_secret'],
        username=config['email'],
        password=config['password'],
        netatmo_url=config['netatmo_url'],
        scope='read_station'
    )

    updated_tokens = {}
    last_refresh = {}
    while True:
        netatmo.publisher.start()
        apartments = get_apartments(registry_url=config['registry_url'])
        for apartment in apartments:
            try:
                apartment_id, mac_address, access_token, refresh_token, sensors = process_netatmo_data(apartment)
                
                if apartment_id in updated_tokens:
                    access_token = updated_tokens[apartment_id]['accessToken']
                    refresh_token = updated_tokens[apartment_id]['refreshToken']
                else:
                    updated_tokens[apartment_id] = {
                        'accessToken': access_token,
                        'refreshToken': refresh_token
                    }

                netatmo.refreshToken = refresh_token
                netatmo.registry_url = config['registry_url']
                netatmo.apartment_id = apartment_id
                
                current_time = time.time()
                if apartment_id not in last_refresh or current_time - last_refresh[apartment_id] >= 3600:
                    print(f"Refreshing token for apartment {apartment_id}...")
                    netatmo.manual_refresh(config['registry_url'], apartment_id)
                    last_refresh[apartment_id] = current_time  
                    updated_tokens[apartment_id]['accessToken'] = netatmo._accessToken
                    updated_tokens[apartment_id]['refreshToken'] = netatmo.refreshToken
                else:
                    print(f"Skipping token refresh for apartment {apartment_id}. Last refresh was {int((current_time - last_refresh[apartment_id]) / 60)} minutes ago.")

                updated_tokens[apartment_id]['accessToken'] = netatmo._accessToken
                updated_tokens[apartment_id]['refreshToken'] = netatmo.refreshToken
                
                valid_access_token = netatmo._accessToken
                print("Using access token:", valid_access_token)
                get_data(netatmo.first_request, apartment_id, mac_address, valid_access_token, sensors)
                netatmo.first_request = False  
            except Exception as e:
                print(f"Error processing apartment {apartment.get('apartmentId', 'unknown')}: {e}")
                continue

        netatmo.publisher.stop()
        print("Sleeping for 30 minutes...")
        time.sleep(1800) 