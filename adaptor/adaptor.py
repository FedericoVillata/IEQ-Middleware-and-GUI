from datetime import datetime
from influxdb_client import InfluxDBClient, Point, WritePrecision, BucketRetentionRules
from influxdb_client.client.write_api import SYNCHRONOUS
import json
import cherrypy
import paho.mqtt.client as PahoMQTT
import time
import threading
from pathlib import Path
import requests
from requests.exceptions import HTTPError
import queue

P = Path(__file__).parent.absolute()
SETTINGS = P / "settings.json"

def CORS():
        cherrypy.response.headers["Access-Control-Allow-Origin"] = "*"
        cherrypy.response.headers["Access-Control-Allow-Methods"] = "GET, POST, PUT, DELETE, OPTIONS"
        cherrypy.response.headers["Access-Control-Allow-Headers"] = "Content-Type"

        if cherrypy.request.method == "OPTIONS":
            cherrypy.response.status = 200
            cherrypy.response.body = b""
            cherrypy.serving.request.handled = True


def get_request(url):
    """Function to try multiple requests if errors are encountered"""
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

def senmlToInflux(senml):
    """Change data format from senML to influxDB standard, including time."""
    output = []   
    for e in senml["e"]:
        point = {
            "measurement": e["n"].split("/")[1],
            "tags": {"unit": e["u"], "MAC": e["n"].split("/")[2]},
            "fields": {e["n"].split("/")[0]: e["v"]},
            "time": int(float(e["t"]) * 1e9)
        }
        output.append(point)
    return output


class Adaptor(object):
    """WebServer for the adaptor"""
    exposed=True
    def __init__(self):
        with open(SETTINGS, 'r') as file:
                settings = json.load(file)
        self.token = settings["influx_token"]
        self.org = settings["influx_org"]
        self.url = settings["adaptor_url"]
        self.influxUrl = settings["url_db"]
        self.registryBaseUrl = settings["registry_url"]
        self.possMeasures = settings["measures"]
        self.port = settings["adaptor_port"]
        self.client = InfluxDBClient(url=self.influxUrl, token=self.token)
        self.bucket_api = self.client.buckets_api()
        self.test = settings["test"]
        self.loadUsers()
        
    def loadUsers(self):
        url = self.registryBaseUrl + "/users"
        self.users = get_request(url)
        
    def checkUserPresent(self, userId):
        """Check if user is present"""
        self.loadUsers()
        for user in self.users:
            if user["userId"] == userId:
                return True
        return False
    def checkApartmentPresent(self,userId, apartmentId):
        """CHeck if apartment is present"""
        self.loadUsers()
        for user in self.users:
            if user["userId"] == userId:
                for apt in user["apartments"]:
                    if apt == apartmentId:
                        return True
        return False
                
    def start(self):

        conf={
            '/':{
            'request.dispatch':cherrypy.dispatch.MethodDispatcher(),
            'tools.sessions.on':True,
            "tools.CORS.on": True
            }
        }

        cherrypy.tree.mount(self,'/',conf)
        cherrypy.config.update({'server.socket_port': self.port})
        cherrypy.config.update({'server.socket_host':'0.0.0.0'})
        cherrypy.tools.CORS = cherrypy.Tool('before_handler', CORS)
        cherrypy.engine.start()
        #cherrypy.engine.block()
        
    def stop(self):
        pass
        
    def GET(self,*uri,**params):
        """Get data from InfluxDB"""
        #http://localhost:8080/getApartmentData/userId/aptId/?measurement=humidity&duration=1 
        if len(uri)!=0:
            if uri[0] == "getApartmentData":
                if self.checkUserPresent(uri[1]):
                    if self.checkApartmentPresent(uri[1],uri[2]): 
                        if params["measurement"] in self.possMeasures:
                            try:
                                duration = int(params["duration"])
                            except:
                                raise cherrypy.HTTPError("400", "invalid duration")
                            if self.test == 1:
                                timeInterval = "m"
                            else:
                                timeInterval = "h"
                            bucket = uri[2]
                            query = f'from(bucket: "{bucket}") \
                                |> range(start: -{duration}{timeInterval}) \
                                        |> filter(fn: (r) => r["_field"] == "{params["measurement"]}")'
                            tables = self.client.query_api().query(org=self.org, query=query)
                            out = []
                            for table in tables:
                                for row in table.records:
                                    line = {"t": row.get_time().strftime("%m/%d/%Y, %H:%M:%S"), "v": row.get_value(), "room": row["_measurement"]}
                                    out.append(line)
                            return json.dumps(out)
                    else:
                        raise cherrypy.HTTPError("400", "Invalid plantCode")                    
                else:
                    raise cherrypy.HTTPError("400", "Invalid User")
            elif uri[0] == "getAllApartmentData":
                #http://localhost:8080/getAllApartmentData/userId/aptId/?duration=1 
                if self.checkUserPresent(uri[1]):
                    if self.checkApartmentPresent(uri[1],uri[2]): 
                        try:
                            duration = int(params["duration"])
                        except:
                            raise cherrypy.HTTPError("400", "invalid duration")
                        if self.test == 1:
                            timeInterval = "m"
                        else:
                            timeInterval = "h"
                        bucket = uri[2]
                        query = f'from(bucket: "{bucket}") \
                            |> range(start: -{duration}{timeInterval})'
                        tables = self.client.query_api().query(org=self.org, query=query)
                        out = []
                        for table in tables:
                            for row in table.records:
                                line = {"t": row.get_time().strftime("%m/%d/%Y, %H:%M:%S"), "v": row.get_value(), "room": row["_measurement"], "measurement": row["_field"]}
                                out.append(line)
                        return json.dumps(out)
                    else:
                        raise cherrypy.HTTPError("400", "Invalid plantCode")                    
                else:
                    raise cherrypy.HTTPError("400", "Invalid User")
            elif uri[0] == "getRoomData":
                #http://localhost:8080/getRoomData/userId/aptId/roomCode?measurement=humidity&duration=1 
                if self.checkUserPresent(uri[1]):
                    if self.checkApartmentPresent(uri[1],uri[2]): 
                        if params["measurement"] in self.possMeasures:
                            try:
                                duration = int(params["duration"])
                            except:
                                raise cherrypy.HTTPError("400", "invalid duration")
                            if self.test == 1:
                                timeInterval = "m"
                            else:
                                timeInterval = "h"
                            bucket =  uri[2]
                            query = f'from(bucket: "{bucket}") \
                                |> range(start: -{duration}{timeInterval}) \
                                    |> filter(fn: (r) => r["_measurement"] == "{uri[3]}") \
                                        |> filter(fn: (r) => r["_field"] == "{params["measurement"]}")'
                            tables = self.client.query_api().query(org=self.org, query=query)
                            out = []
                            for table in tables:
                                for row in table.records:
                                    line = {"t": row.get_time().strftime("%m/%d/%Y, %H:%M:%S"), "v": row.get_value()}
                                    out.append(line)
                            return json.dumps(out)
                    else:
                        raise cherrypy.HTTPError("400", "Invalid plantCode")                    
                else:
                    raise cherrypy.HTTPError("400", "Invalid User")
            elif uri[0] == "getAllRoomData":
                #http://localhost:8080/getAllRoomData/userId/aptId/roomCode?duration=1 
                if self.checkUserPresent(uri[1]):
                    if self.checkApartmentPresent(uri[1],uri[2]): 
                        
                        try:
                            duration = int(params["duration"])
                        except:
                            raise cherrypy.HTTPError("400", "invalid duration")
                        if self.test == 1:
                            timeInterval = "m"
                        else:
                            timeInterval = "h"
                        bucket =  uri[2]
                        query = f'from(bucket: "{bucket}") \
                            |> range(start: -{duration}{timeInterval}) \
                                |> filter(fn: (r) => r["_measurement"] == "{uri[3]}")'
                        tables = self.client.query_api().query(org=self.org, query=query)
                        out = []
                        for table in tables:
                            for row in table.records:
                                line = {"t": row.get_time().strftime("%m/%d/%Y, %H:%M:%S"), "v": row.get_value(), "measurement": row["_field"]}
                                out.append(line)
                        return json.dumps(out)
                    else:
                        raise cherrypy.HTTPError("400", "Invalid plantCode")                    
                else:
                    raise cherrypy.HTTPError("400", "Invalid User")
                    
            elif uri[0] == "getLastRoomData":
                #http://localhost:8080/getLastRoomData/userId/aptId/roomCode
                if self.checkUserPresent(uri[1]):
                    if self.checkApartmentPresent(uri[1],uri[2]): 
                        bucket =  uri[2]
                        query = f'from(bucket: "{bucket}") \
                            |> range(start: -4h) \
                                |> filter(fn: (r) => r["_measurement"] == "{uri[3]}") \
                                    |> last()'
                        tables = self.client.query_api().query(org=self.org, query=query)
                        out = []
                        for table in tables:
                            for row in table.records:
                                line = {"t": row.get_time().strftime("%m/%d/%Y, %H:%M:%S"), "v": row.get_value(), "measurement": row["_field"]}
                                out.append(line)
                        return json.dumps(out)
                    else:
                        raise cherrypy.HTTPError("400", "Invalid plantCode")                    
                else:
                    raise cherrypy.HTTPError("400", "Invalid User")
            elif uri[0] == "getLastData":
                #http://localhost:8080/getLastData/userId/aptId/
                if self.checkUserPresent(uri[1]):
                    if self.checkApartmentPresent(uri[1],uri[2]): 
                        bucket =  uri[2]
                        query = f'from(bucket: "{bucket}") \
                            |> range(start: -4h) \
                                |> last()'
                        tables = self.client.query_api().query(org=self.org, query=query)
                        out = []
                        for table in tables:
                            for row in table.records:
                                line = {"t": row.get_time().strftime("%m/%d/%Y, %H:%M:%S"), "v": row.get_value(), "room": row["_measurement"], "measurement": row["_field"]}
                                out.append(line)
                        return json.dumps(out)
                    else:
                        raise cherrypy.HTTPError("400", "Invalid plantCode")                    
                else:
                    raise cherrypy.HTTPError("400", "Invalid User")
            elif uri[0] == "getDataInPeriod":
                #http://localhost:8080/getDatainPeriod/userId/aptId/?measurement=Temperature&start=2025-03-20T08:00:00Z&stop=2025-03-21T08:00:00Z
                #time in RFC3339 format
                if self.checkUserPresent(uri[1]):
                    if self.checkApartmentPresent(uri[1],uri[2]): 
                        if params["measurement"] in self.possMeasures:
                            try:
                                start = params["start"]  # Get start date
                                stop = params["stop"]    # Get stop date
                            except KeyError:
                                raise cherrypy.HTTPError("400", "Missing start or stop date")
                            if self.test == 1:
                                timeInterval = "m"
                            else:
                                timeInterval = "h"
                            bucket = uri[2]
                            query = f'from(bucket: "{bucket}") \
                                |> range(start: {start}, stop: {stop}) \
                                        |> filter(fn: (r) => r["_field"] == "{params["measurement"]}")'
                            tables = self.client.query_api().query(org=self.org, query=query)
                            out = []
                            for table in tables:
                                for row in table.records:
                                    line = {"t": row.get_time().strftime("%m/%d/%Y, %H:%M:%S"), "v": row.get_value(), "room": row["_measurement"]}
                                    out.append(line)
                            return json.dumps(out)
                    else:
                        raise cherrypy.HTTPError("400", "Invalid plantCode")                    
                else:
                    raise cherrypy.HTTPError("400", "Invalid User")   
            else:
                raise cherrypy.HTTPError("400", "Invalid operation")     
        else:
            raise cherrypy.HTTPError("400", "no uri")
        

    def PUT(self,*uri,**params):
        return  
    
    def POST(self,*uri,**params):
        """Add user bucket"""
        if uri[0] == "addApartment":
            body = json.loads(cherrypy.request.body.read())  # Read body data
            self.addBucket( body["apartmentId"])
            response = {"status": "OK", "code": 200}
            return response 
    def DELETE(self,*uri,**params):
        """Delete user bucket"""
        if uri[0] == "deleteApartment":
            self.deleteUserBuckets(uri[1])
            print(f"Deleted {uri[1]}'s buckets")
            response = {"status": "OK", "code": 200}
            return response   

    def addBucket(self, apartmentId):  
        "Function that adds bucket to Influx"
        retention_rules = BucketRetentionRules(type="expire", every_seconds=2592000)
        created_bucket = self.bucket_api.create_bucket(bucket_name=apartmentId, retention_rules = retention_rules,org = self.org)
        print(created_bucket)
        
    def listBuckets(self):
        """Get list of buckets from Influx"""
        buckets = self.bucket_api.find_buckets().buckets
        return buckets
    
    def deleteUserBuckets(self, userID):
        """Delete buket from Influx"""
        buckets = self.listBuckets()
        for bucket in buckets:
            if bucket.name.startswith(userID):
                self.bucket_api.delete_bucket(bucket)
                print(f"Succesfully deleted bucket: {bucket.name}")

class MySubscriber:
    def __init__(self, clientID, topic, broker, port, write_api):
        self.clientID = clientID
        self._paho_mqtt = PahoMQTT.Client(clientID, False) 
        self._paho_mqtt.on_connect = self.myOnConnect
        self._paho_mqtt.on_message = self.myOnMessageReceived 
        self.write_api = write_api
        self.topic = topic
        self.messageBroker = broker
        self.port = port
        with open(SETTINGS, 'r') as file:
            data = json.load(file)
        self.measures = data["measures"]
        self.org = data["influx_org"]
        self.registry_url = data["registry_url"]
        url = self.registry_url + "/apartments"
        self.apartments = get_request(url)
        self.time = time.time()
        
        # Initialize message queue
        self.message_queue = queue.Queue()
        self.processing_thread = threading.Thread(target=self.process_messages, daemon=True)
        self.processing_thread.start()

    def update_apartments(self):
        url = self.registry_url + "/apartments"
        self.apartments = get_request(url)

    def start(self):
        self._paho_mqtt.connect(self.messageBroker, self.port)
        self._paho_mqtt.loop_start()
        self._paho_mqtt.subscribe(self.topic, 2)

    def stop(self):
        self._paho_mqtt.unsubscribe(self.topic)
        self._paho_mqtt.loop_stop()
        self._paho_mqtt.disconnect()

    def myOnConnect(self, paho_mqtt, userdata, flags, rc):
        print("Connected to %s with result code: %d" % (self.messageBroker, rc))

    def checkApartmentPresence(self, apartmentId):
        if time.time() > self.time + 60:
            self.update_apartments()
            self.time = time.time()
        return any(apt["apartmentId"] == apartmentId for apt in self.apartments)

    def checkBnNotAlive(self, bn):
        return bn not in ["updateCatalogDevice", "updateCatalogService"]
    
    def checkIfNotSuggestion(self, topic):
        if len(topic.split("/")) > 2:
            if topic.split("/")[2] == "suggestion":
                return False
        return True
    def myOnMessageReceived(self, paho_mqtt, userdata, msg):
        """Push received messages to the queue instead of processing immediately"""
        print("Message received on topic:", msg.topic)
        self.message_queue.put(msg)

    def process_messages(self):
        """Worker thread to process messages from the queue"""
        while True:
            msg = self.message_queue.get()
            if msg:
                try:
                    topic_parts = msg.topic.split("/")
                    apartmentId = topic_parts[1]
                    msgJson = json.loads(msg.payload)

                    if (
                        self.checkApartmentPresence(apartmentId) and
                        self.checkBnNotAlive(msgJson.get("bn")) and
                        self.checkIfNotSuggestion(msg.topic)
                    ):
                        converted = senmlToInflux(msgJson)

                        if converted:
                            print(f"Writing {len(converted)} points to InfluxDB for apartment {apartmentId}")
                            # Batch write
                            self.write_api.write(bucket=apartmentId, org=self.org, record=converted)
                            # Update sensor registry if topic indicates sensor data
                            if len(topic_parts) > 2 and topic_parts[2] == "sensorData":
                                url = self.registry_url + "/update_sensors"
                                headers = {"Content-Type": "application/json"}
                                message = {
                                    "apartmentId": apartmentId,
                                    "points": converted
                                }
                                response = requests.put(url, headers=headers, data=json.dumps(message))

                                if response.status_code == 200:
                                    print("Sensor update data sent to registry")
                                else:
                                    print(f"Failed to send data to registry: {response.status_code}")
                        else:
                            print("No valid points converted from message.")
                    else:
                        print("Invalid message or skipped based on filters.")
                except Exception as e:
                    print("Error processing message:", e)
                finally:
                    self.message_queue.task_done()

# Threads
class MQTTreciver(threading.Thread):
    """Subscriber that uploads messages into DB and sends alive messages"""
    def __init__(self, ThreadID, name):
        """Initialise thread widh ID and name."""
        threading.Thread.__init__(self)
        self.ThreadID = ThreadID
        self.name = name
        with open(SETTINGS, 'r') as file:
            data = json.load(file)
        self.topic = data["base_topic"]
        self.broker = data["messageBroker"]
        self.mqtt_port = int(data["brokerPort"])
        self.client = InfluxDBClient(url=data["url_db"], token=data["influx_token"])
        self.write_api = self.client.write_api(write_options=SYNCHRONOUS)
        self.alive_topic = data["alive_topic"]
        self.url = data["adaptor_url"]

    def run(self):
        """Run thread."""
        print(self.topic)
        # Start subscriber.
        sub = MySubscriber("IEQ_sub", self.topic, self.broker, self.mqtt_port, self.write_api)
        print("Starting subscriber")
        sub.start()
        #self.pub = MyPublisher("IEQ_pub", self.alive_topic)
        #print("Starting publisher")
        #self.pub.start()  

        while True:
            time.sleep(10)
        ##    print("sending alive message...")
        ##    msg = {"bn": "updateCatalogService", "e":[{"n": "adaptor", "t": time.time(), "u": "URL", "v": self.url}]}
        ##    self.pub.myPublish(json.dumps(msg), self.alive_topic)
        ##    time.sleep(10)

class MyPublisher:
    def __init__(self, clientID, topic):
        self.clientID = clientID
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

    def start (self):
		#manage connection to broker
        self._paho_mqtt.connect(self.messageBroker, self.port)
        self._paho_mqtt.loop_start()

    def stop (self):
        self._paho_mqtt.loop_stop()
        self._paho_mqtt.disconnect()

    def myPublish(self, message, topic):
		# publish a message with a certain topic
        self._paho_mqtt.publish(topic, message, 2)

    def myOnConnect (self, paho_mqtt, userdata, flags, rc):
        print ("Connected to %s with result code: %d" % (self.messageBroker, rc))

if __name__ == '__main__':
    adaptor = Adaptor()
    adaptor.start()
    
    reciver = MQTTreciver(2, "mqttReciver")
    reciver.run()