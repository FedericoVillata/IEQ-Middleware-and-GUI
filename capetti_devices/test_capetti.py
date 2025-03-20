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

        if response.status_code == 401:  # Token expired
            print("UserToken expired. Renewing token...")
            self.get_user_token()
            return self.get_sensor_list(first_request)  # retray with new token

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

        if first_request:
            date_to = int(time.time())
            date_from = date_to - 24 * 3600  # last 24 hours
            self.get_history_values(date_from=date_from, date_to=date_to)
        else:
            self.get_current_values()

    def get_history_values(self, date_from, date_to, start_index=0):
        if not self.token:
            print("Error: User token not available.")
            return

        url = f'{self.base_url}?action=getSystemHistory'
        params = {
            'wliMac': self.mac,
            'dateFrom': date_from,
            'dateTo': date_to
        }
        headers = {
            'Content-Type': 'application/json',
            'Authorization': f"Bearer {self.token}"
        }

        response = requests.get(url=url, params=params, headers=headers, verify=False)

        if response.status_code == 401:  # Token scaduto
            print("UserToken expired. Renewing token...")
            self.get_user_token()
            return self.get_history_values(date_from, date_to, start_index)  # Riprova con il nuovo token

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

        channel_type_mapping = {
        1: ("Temperature", "Celsius"),
        2: ("Relative Humidity", "%"),
        3: ("Light", "Lux"),
        4: ("Deformation", "mm"),
        5: ("CO2 Concentration", "ppm"),
        6: ("Active Electric Energy", "kWh"),
        7: ("Apparent Electric Energy", "kVAh"),
        8: ("Fluid Volume", "L"),
        9: ("Thermal Energy", "kWh"),
        10: ("Tilt Angle", "°"),
        11: ("Contact", "-"),
        12: ("CH4 Concentration", "ppm"),
        13: ("Pressure", "mbar"),
        14: ("Voltage", "V"),
        15: ("Current", "mA"),
        16: ("Proportional", "%"),
        17: ("Thermal Flux", "W/m²"),
        18: ("Frequency", "Hz"),
        19: ("Deformation Ratio", "µV/V"),
        20: ("Speed", "m/s"),
        21: ("Direction", "°"),
        22: ("Solar Radiation", "W/m²"),
        23: ("Current", "A"),
        24: ("Pulses", "-"),
        25: ("MPX8 Index", "-"),
        26: ("Reactive Electric Energy", "kvarh"),
        27: ("Degree Day", "GG"),
        28: ("Acceleration", "g"),
        29: ("Nodes", "-"),
        30: ("Packages", "-"),
        31: ("Cumulative Pulse", "-"),
        32: ("VOC Concentration", "ppm"),
        33: ("CO Concentration", "ppm"),
        34: ("O3 Concentration", "ppm"),
        35: ("NO2 Concentration", "ppm"),
        36: ("CH2O Concentration", "ppm"),
        37: ("TVOC Concentration", "ppb"),
        38: ("Mass Concentration PM1.0", "µg/m³"),
        39: ("Mass Concentration PM2.5", "µg/m³"),
        40: ("Mass Concentration PM4.0", "µg/m³"),
        41: ("Mass Concentration PM10.0", "µg/m³"),
        42: ("Number Concentration PM0.5", "#/cm³"),
        43: ("Number Concentration PM1.0", "#/cm³"),
        44: ("Number Concentration PM2.5", "#/cm³"),
        45: ("Number Concentration PM4.0", "#/cm³"),
        46: ("Number Concentration PM10.0", "#/cm³"),
        47: ("Typical Particle Size", "µm"),
        48: ("Absolute Distance", "mm"),
        49: ("Relative Distance", "mm"),
        50: ("Tilt Angle X", "°"),
        51: ("Tilt Angle Y", "°"),
        52: ("Cumulative Active Electric Energy", "kWh"),
        53: ("Cumulative Apparent Electric Energy", "kVAh"),
        54: ("Cumulative Fluid Volume", "L"),
        55: ("Cumulative Thermal Energy", "kWh"),
        56: ("Cumulative Reactive Electric Energy", "kvarh"),
        57: ("Generic", "-"),
        200: ("Index", "-"),
        254: ("Custom", "-")
        }

        pubTopic = f"IEQmidAndGUI/{self.apartment_id}"
        myPub = MyPublisher("54234")
        myPub.start()

        for index, item in enumerate(data[start_index:], start=start_index):
            sensor_mac = item['sensorMac']
            channel_type = int(item['channelType'])
            value = item['value']
            timestamp = item['timeStamp']
            invalid = int(item['invalid'])
            alarm = int(item['alarm'])

            if invalid == 1 or alarm == 1 or value == '':
                continue
            if channel_type not in channel_type_mapping:
                continue

            measure_type, unit = channel_type_mapping[channel_type]

            if sensor_mac in self.sensor_room_mapping:
                room_id = self.sensor_room_mapping[sensor_mac]
                # Costruisci il campo `n`
                n_field = f"{measure_type}/{room_id}/{sensor_mac}"
                if "/" not in n_field or len(n_field.split("/")) < 3:
                    print(f"Invalid 'n' field: {n_field}")
                    continue  # Salta se il campo `n` non è valido

                event = {
                    "n": n_field,
                    "u": unit,
                    "t": str((int(timestamp))),
                    "v": float(value)
                }
                out = {"bn": pubTopic, "e": [event]}
                print(f"Publishing message: {out}")
                myPub.myPublish(json.dumps(out), pubTopic)

            # Salva l'indice corrente in caso di errore
            start_index = index
            time.sleep(0.1)
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
        channel_type_mapping = {
        1: ("Temperature", "Celsius"),
        2: ("Relative Humidity", "%"),
        3: ("Light", "Lux"),
        4: ("Deformation", "mm"),
        5: ("CO2 Concentration", "ppm"),
        6: ("Active Electric Energy", "kWh"),
        7: ("Apparent Electric Energy", "kVAh"),
        8: ("Fluid Volume", "L"),
        9: ("Thermal Energy", "kWh"),
        10: ("Tilt Angle", "°"),
        11: ("Contact", "-"),
        12: ("CH4 Concentration", "ppm"),
        13: ("Pressure", "mbar"),
        14: ("Voltage", "V"),
        15: ("Current", "mA"),
        16: ("Proportional", "%"),
        17: ("Thermal Flux", "W/m²"),
        18: ("Frequency", "Hz"),
        19: ("Deformation Ratio", "µV/V"),
        20: ("Speed", "m/s"),
        21: ("Direction", "°"),
        22: ("Solar Radiation", "W/m²"),
        23: ("Current", "A"),
        24: ("Pulses", "-"),
        25: ("MPX8 Index", "-"),
        26: ("Reactive Electric Energy", "kvarh"),
        27: ("Degree Day", "GG"),
        28: ("Acceleration", "g"),
        29: ("Nodes", "-"),
        30: ("Packages", "-"),
        31: ("Cumulative Pulse", "-"),
        32: ("VOC Concentration", "ppm"),
        33: ("CO Concentration", "ppm"),
        34: ("O3 Concentration", "ppm"),
        35: ("NO2 Concentration", "ppm"),
        36: ("CH2O Concentration", "ppm"),
        37: ("TVOC Concentration", "ppb"),
        38: ("Mass Concentration PM1.0", "µg/m³"),
        39: ("Mass Concentration PM2.5", "µg/m³"),
        40: ("Mass Concentration PM4.0", "µg/m³"),
        41: ("Mass Concentration PM10.0", "µg/m³"),
        42: ("Number Concentration PM0.5", "#/cm³"),
        43: ("Number Concentration PM1.0", "#/cm³"),
        44: ("Number Concentration PM2.5", "#/cm³"),
        45: ("Number Concentration PM4.0", "#/cm³"),
        46: ("Number Concentration PM10.0", "#/cm³"),
        47: ("Typical Particle Size", "µm"),
        48: ("Absolute Distance", "mm"),
        49: ("Relative Distance", "mm"),
        50: ("Tilt Angle X", "°"),
        51: ("Tilt Angle Y", "°"),
        52: ("Cumulative Active Electric Energy", "kWh"),
        53: ("Cumulative Apparent Electric Energy", "kVAh"),
        54: ("Cumulative Fluid Volume", "L"),
        55: ("Cumulative Thermal Energy", "kWh"),
        56: ("Cumulative Reactive Electric Energy", "kvarh"),
        57: ("Generic", "-"),
        200: ("Index", "-"),
        254: ("Custom", "-")
        }

        pubTopic = f"IEQmidAndGUI/{self.apartment_id}"
        myPub = MyPublisher("54234")
        myPub.start()

        for item in data:
            sensor_mac = item['sensorMac']
            channel_type = int(item['channelType'])
            value = item['value']
            timestamp = item['timeStamp']
            invalid = int(item['invalid'])
            alarm = int(item['alarm'])

            

            measure_type, unit = channel_type_mapping[channel_type]

            if sensor_mac in self.sensor_room_mapping:
                room_id = self.sensor_room_mapping[sensor_mac]
                # Costruisci il campo `n`
                n_field = f"{measure_type}/{room_id}/{sensor_mac}"
                if "/" not in n_field or len(n_field.split("/")) < 3:
                    print(f"Invalid 'n' field: {n_field}")
                    continue  # Salta se il campo `n` non è valido

                event = {
                    "n": n_field,
                    "u": unit,
                    "t": str((int(timestamp))),
                    "v": float(value)
                }
                out = {"bn": pubTopic, "e": [event]}
                print(f"Publishing message: {out}")
                myPub.myPublish(json.dumps(out), pubTopic)
            time.sleep(0.1)

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
            time.sleep(40)  # 10 minutes