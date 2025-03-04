from datetime import datetime
import requests
import json

class CapettiAPI:
    def __init__(self, username, rest_license, mac):
        self.username = username
        self.rest_license = rest_license
        self.mac = mac
        self.base_url = 'https://www.winecap.it/api/v1/'
        self.token = None

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

    def get_current_values(self):
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
            'name': [],  #./netatmo_config.json
            'channel': [],
            'value': []
        }

        for item in data:
            if item['sensorMac'] == '0000E795':  # Filter for specific sensor
                values['sensorName'].append(item['sensorName'])
                values['sensorMac'].append(item['sensorMac'])
                values['channel'].append(item['channel'])
                values['channelType'].append(item['channelType'])
                values['timestamp'].append(datetime.utcfromtimestamp(int(item['timeStamp'])))
                values['value'].append(item['value'])
                values['invalid'].append(item['invalid'])
                values['alarm'].append(item['alarm'])

        sensor['name'].append(values['sensorName'][0])
        sensor['channel'].append(values['channel'][0])
        sensor['value'].append(values['value'][0])

        print(values)

# Esempio di utilizzo:
capetti = CapettiAPI(
    username='Polito_IP24',
    rest_license='fzfir7ihlzoapqs82p18lc90t67eu1',
    mac='0000F28F'
)

capetti.get_user_token()
capetti.get_current_values()