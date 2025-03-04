import requests
from datetime import datetime, timedelta
import pandas as pd
import json
import matplotlib.pyplot as plt
import numpy as np
import time
from os import getenv
from os.path import expanduser

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
        if self.first_request:
            date_start = datetime.now() - timedelta(days=1)
            self.first_request = False
        else:
            date_start = datetime.now() - timedelta(minutes=30)
        
        date_start = int(date_start.replace(tzinfo=None).timestamp())
        date_end = int(datetime.now().timestamp())

        for module_name, module_id in self.modules.items():
            url = f'{self.base_url}/api/getmeasure'
            params = {
                'device_id': self.mac,
                'module_id': module_id,
                'scale': '30min',
                'type': 'temperature,humidity,co2,pressure,noise',
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
                'temperature': [val[0] for val in body['value']],
                'humidity': [val[1] for val in body['value']],
                'co2': [val[2] for val in body['value']],
                'pressure': [val[3] for val in body['value']],
                'noise': [val[4] for val in body['value']]
            }

            datetime_start = datetime.fromtimestamp(body['beg_time'])
            step_time = body.get('step_time', 1)

            values['timestamp'] = [datetime_start + timedelta(seconds=i * step_time) for i in range(len(values['temperature']))]

            self.data[module_name] = pd.DataFrame.from_dict(values)
            self.data[module_name] = self.data[module_name].set_index('timestamp')
            print(f"Data for {module_name}:")
            print(self.data[module_name].head())

            json_data = {
                "module_name": module_name,
                "measurements": self.data[module_name].to_dict(orient='records')
            }
            # Print data in JSON format
            print(json.dumps(json_data, indent=4))

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

if __name__ == '__main__':
    
    with open('netatmo_config.json') as config_file:
        config = json.load(config_file)

    
    modules = {
        'stanza 1': config['mac'],  # Main module
        'stanza 2': '03:00:00:0c:e0:b2',      # Internal module 1
        'stanza 3': '03:00:00:0c:e0:98',      # Internal module 2
        'stanza 4': '03:00:00:0d:34:20',      # Internal module 3
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