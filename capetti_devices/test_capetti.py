from datetime import datetime, timedelta
import requests
import json
import time
from pathlib import Path
import paho.mqtt.client as PahoMQTT

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

def process_capetti_data(apartment_data):
    sensor_room_mapping = {}
    for mac_entry in apartment_data['MAC']:
        if mac_entry['name'] == "capetti":
            mac_address = mac_entry['MAC']
            for room in apartment_data['rooms']:
                for sensor in room['sensors']:
                    sensor_room_mapping[sensor] = room['roomId']
            return mac_address, sensor_room_mapping
    raise Exception("No MAC entry with name 'capetti' found.")

class CapettiAPI:
    def __init__(self, username, rest_license, mac, apartment_id, sensor_room_mapping):
        self.username = username
        self.rest_license = rest_license
        self.mac = mac
        self.apartment_id = apartment_id
        self.sensor_room_mapping = sensor_room_mapping
        self.base_url = 'https://www.winecap.it/api/v1/'
        self.token = None
        self.first_request = True

    def get_user_token(self):
        url = f'{self.base_url}?action=getUserToken&Login={self.username}&RESTLicense={self.rest_license}'
        headers = {'Content-Type': 'application/json'}
        response = requests.post(url=url, headers=headers, verify=True)

        if response.status_code == 200:
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
        params = {'wliMac': self.mac}
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
            if item['sensorMac'] in self.sensor_room_mapping:
                room_id = self.sensor_room_mapping[item['sensorMac']]
                if first_request:
                    for channel in [1, 2, 3, 4]:  # Itera su tutti i canali
                        self.get_history_values(sensor_mac=item['sensorMac'], sensor_ch=channel, room_id=room_id)
                else:
                    self.get_current_values()

    def get_history_values(self, sensor_mac, sensor_ch, room_id):
        if not self.token:
            print("Error: User token not available.")
            return

        date_to = int(time.time())
        date_from = date_to - 24 * 3600  # 24 hours

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

        pubTopic = f"IEQmidAndGUI/{self.apartment_id}"
        myPub = MyPublisher("54234")
        myPub.start()

        for item in data:
            value = item['value']
            timestamp = item['timeStamp']
            if value == '':
                continue

            if sensor_ch == 1:# channel type
                measure_type = "Temperature"
                unit = "Celsius"
            elif sensor_ch == 2:
                measure_type = "Humidity" if sensor_mac not in ["0000F258", "0000F257"] else "CO2"
                unit = "%" if sensor_mac not in ["0000F258", "0000F257"] else "ppm"
            elif sensor_ch == 3:
                if sensor_mac in ["0000F258", "0000F257"]:
                    measure_type = "PM2.5"
                    unit = "µg/m3"
                elif sensor_mac == "0000F264":
                    measure_type = "VOC"
                    unit = "ppb"
                else:
                    measure_type = "CO2"
                    unit = "ppm"
            elif sensor_ch == 4:
                measure_type = "Pressure" if sensor_mac not in ["0000F258", "0000F257"] else "PM10"
                unit = "hPa" if sensor_mac not in ["0000F258", "0000F257"] else "µg/m3"
            else:
                continue  

            event = {
                "n": f"{measure_type}/{room_id}/{sensor_mac}",
                "u": unit,
                "t": str((int(timestamp))),
                "v": float(value)
            }
            out = {"bn": pubTopic, "e": [event]}
            print(out)
            myPub.myPublish(json.dumps(out), pubTopic)
            time.sleep(0.2)

    def get_current_values(self):
        pubTopic = f"IEQmidAndGUI/{self.apartment_id}"
        if not self.token:
            print("Error: User token not available.")
            return

        url = f'{self.base_url}?action=getCurrentValues'
        params = {'wliMac': self.mac}
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

        myPub = MyPublisher("54234")
        myPub.start()
        for item in data:
            sensor_mac = item['sensorMac']
            if sensor_mac in self.sensor_room_mapping:
                room_id = self.sensor_room_mapping[sensor_mac]
                channels = item.get('channels', {})

                for channel, value in channels.items():
                    if channel == 1:
                        measure_type = "Temperature"
                        unit = "Celsius"
                    elif channel == 2:
                        measure_type = "Humidity" if sensor_mac not in ["0000F258", "0000F257"] else "CO2"
                        unit = "%" if sensor_mac not in ["0000F258", "0000F257"] else "ppm"
                    elif channel == 3:
                        if sensor_mac in ["0000F258", "0000F257"]:
                            measure_type = "PM2.5"
                            unit = "µg/m3"
                        elif sensor_mac == "0000F264":
                            measure_type = "VOC"
                            unit = "ppb"
                        else:
                            measure_type = "CO2"
                            unit = "ppm"
                    elif channel == 4:
                        measure_type = "Pressure" if sensor_mac not in ["0000F258", "0000F257"] else "PM10"
                        unit = "hPa" if sensor_mac not in ["0000F258", "0000F257"] else "µg/m3"
                    else:
                        continue

                    event = {
                        "n": f"{measure_type}/{room_id}/{sensor_mac}",
                        "u": unit,
                        "t": str((int(item['timeStamp']))),
                        "v": float(value)
                    }
                    out = {"bn": pubTopic, "e": [event]}
                    print(out)
                    myPub.myPublish(json.dumps(out), pubTopic)

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
    with open('./config_capetti.json') as config_file:
        config = json.load(config_file)

    users = get_users()
    apartments = get_apartments()

    for apartment in apartments:
        try:
            mac_address, sensor_room_mapping = process_capetti_data(apartment)
        except Exception as e:
            print(e)
            continue

        apartment_id = apartment['apartmentId']
        capetti = CapettiAPI(
            username=config['username'],
            rest_license=config['rest_license'],
            mac=mac_address,
            apartment_id=apartment_id,
            sensor_room_mapping=sensor_room_mapping
        )

        capetti.get_user_token()

        while True:
            capetti.get_sensor_list(capetti.first_request)
            capetti.first_request = False
            time.sleep(10)  # 10 minutes