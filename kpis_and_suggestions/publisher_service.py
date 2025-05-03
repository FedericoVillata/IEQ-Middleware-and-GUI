# publisher_service.py
import time
import json
from datetime import datetime

def log(message, level="INFO", context=None):
    timestamp = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    prefix = f"[{timestamp}] [{level}]"
    # prefix = f"[{level}]"
    if context:
        prefix += f" [{context}]"
    print(f"{prefix} {message}")



def publish_room_metrics(publisher, base_topic, apartment_id, room_id, metrics):
    topic = f"{base_topic}/{apartment_id}"
    timestamp = time.time()

    events = [
        {"n": f"avg_temperature/{room_id}/value", "u": "Cel", "t": timestamp, "v": metrics.get("avg_temp")},
        {"n": f"temperature_class/{room_id}/class", "u": "class", "t": timestamp, "v": metrics.get("temp_class")},
        {"n": f"avg_humidity/{room_id}/value", "u": "%RH", "t": timestamp, "v": metrics.get("avg_humidity")},
        {"n": f"humidity_class/{room_id}/class", "u": "class", "t": timestamp, "v": metrics.get("hum_class")},
        {"n": f"avg_co2/{room_id}/value", "u": "ppm", "t": timestamp, "v": metrics.get("avg_co2")},
        {"n": f"co2_class/{room_id}/class", "u": "class", "t": timestamp, "v": metrics.get("co2_class")},
        {"n": f"pmv/{room_id}/value", "u": "arb", "t": timestamp, "v": metrics.get("pmv")},
        {"n": f"pmv_class/{room_id}/class", "u": "class", "t": timestamp, "v": metrics.get("pmv_class")},
        {"n": f"ppd/{room_id}/value", "u": "%", "t": timestamp, "v": metrics.get("ppd")},
        {"n": f"ppd_class/{room_id}/class", "u": "class", "t": timestamp, "v": metrics.get("ppd_class")},
        {"n": f"icone/{room_id}/value", "u": "arb", "t": timestamp, "v": metrics.get("icone")},
        {"n": f"icone_class/{room_id}/class", "u": "class", "t": timestamp, "v": metrics.get("icone_class")},
        {"n": f"ieqi/{room_id}/value", "u": "arb", "t": timestamp, "v": metrics.get("ieqi")},
        {"n": f"ieqi_class/{room_id}/class", "u": "class", "t": timestamp, "v": metrics.get("ieqi_class")},
        {"n": f"environment_score/{room_id}/value", "u": "score", "t": timestamp, "v": metrics.get("env_score")},
        {"n": f"environment_score_class/{room_id}/class", "u": "class", "t": timestamp, "v": metrics.get("env_classification")},
    ]

    if metrics.get("adaptive_comfort"):
        events.extend([
            {
                "n": f"adaptive_comfort_running_mean/{room_id}/value",
                "u": "value",
                "t": timestamp,
                "v": metrics["adaptive_comfort"].get("Running Mean Temperature", -999)
            },
            {
                "n": f"adaptive_comfort_t_comf/{room_id}/value",
                "u": "value",
                "t": timestamp,
                "v": metrics["adaptive_comfort"].get("Comfort Temperature", -999)
            },
        ])

    for event in events:
        payload = {"bn": topic, "e": [event]}
        log(f"Publishing event: {event['n']}", level="DEBUG", context=f"{apartment_id}/{room_id}")
        #print(json.dumps(payload, indent=2))
        publisher.myPublish(json.dumps(payload), topic)


def publish_tenant_suggestions(publisher, base_topic, apartment_id, room_id, suggestions):
    if not suggestions:
        return

    topic = f"{base_topic}/{apartment_id}/tenant_suggestion"
    timestamp = time.time()

    for suggestion_id, tip in suggestions.items():
        event = {
            "bn": topic,
            "e": [{
                "n": f"{room_id}/{suggestion_id}",  # ID diretto
                "t": timestamp,
                "u": "string",
                "v": tip
            }]
        }

        log(f"Tenant suggestion: {suggestion_id} = '{tip}'", level="DEBUG", context=f"{apartment_id}/{room_id}")
        #print(json.dumps(payload, indent=2))
        publisher.myPublish(json.dumps(event), topic)


def publish_technical_suggestions(publisher, base_topic, apartment_id, suggestions):
    if not suggestions:
        return

    topic = f"{base_topic}/{apartment_id}/technical_suggestion"
    timestamp = time.time()

    for key, tip in suggestions.items():
        event = {
            "bn": topic,
            "e": [{
                "n": f"{key}",
                "t": timestamp,
                "u": "string",
                "v": tip
            }]
        }
        log(f"Technical suggestion: {key} = '{tip}'", level="DEBUG", context=apartment_id)
        #print(json.dumps(payload, indent=2))
        publisher.myPublish(json.dumps(event), topic)


def publish_alerts(publisher, base_topic, apartment_id, room_id, classifications, sensor_alerts=None):
    critical_labels = ["R", "Extreme", "Very Cold", "Very Warm"]
    timestamp = time.time()
    topic = f"{base_topic}/{apartment_id}/alert"

    for metric, label in classifications.items():
        if label in critical_labels:
            alert_event = {
                "bn": topic,
                "e": [{
                    "n": f"{room_id}",
                    "t": timestamp,
                    "u": "alert",
                    "v": f"{metric} classified as {label}"
                }]
            }
            log(f"ALERT: {metric} classified as {label}", level="WARN", context=f"{apartment_id}/{room_id}")
            #print(json.dumps(payload, indent=2))
            publisher.myPublish(json.dumps(alert_event), topic)

    if sensor_alerts:
        for alert in sensor_alerts:
            alert_event = {
                "bn": topic,
                "e": [{
                    "n": alert["sensor_name"],
                    "t": timestamp,
                    "u": "alert",
                    "v": alert["message"]
                }]
            }
            log(f"Sensor Alert | Apartment: {apartment_id} | Room/Sensor: {alert["sensor_name"]} | Issue: {alert['message']}", level="WARN")
            publisher.myPublish(json.dumps(alert_event), topic)        


# --- MQTT Publisher Class ---
import paho.mqtt.client as PahoMQTT
import threading

class MyPublisher:
    
    def __init__(self, clientID, base_topic, broker="localhost", port=1883, qos=2):
        self.clientID = clientID
        self.base_topic = base_topic

        # Create MQTT client with explicit protocol version and API compatibility
        self._paho_mqtt = PahoMQTT.Client(client_id=self.clientID, clean_session=False, protocol=PahoMQTT.MQTTv311)
        self._paho_mqtt.enable_logger()

        # Assign callbacks
        self._paho_mqtt.on_connect = self.myOnConnect
        self._paho_mqtt.on_publish = self.myOnPublish

        # Broker parameters
        self.messageBroker = broker
        self.port = port
        self.qos = qos  # Default to QoS 2 for high reliability

        self._pending_messages = 0
        self._lock = threading.Lock()
        self._all_sent_event = threading.Event()
        self._all_sent_event.set()  # Start unblocked


    def start(self):
        try:
            self._paho_mqtt.connect(self.messageBroker, self.port)
            self._paho_mqtt.loop_start()
            log(f"Connecting to MQTT broker at {self.messageBroker}:{self.port}", context=self.clientID)
        except Exception as e:
            log(f"Failed to connect to MQTT broker: {e}", level="ERROR", context=self.clientID)

    def stop(self):
        log("Waiting for all MQTT messages to be published...", context=self.clientID)
        self._all_sent_event.wait(timeout=10)  # Max 10 sec wait
        self._paho_mqtt.loop_stop()
        self._paho_mqtt.disconnect()
        log("Disconnected from MQTT broker.", context=self.clientID)



    def myPublish(self, message, topic):
        try:
            clean_topic = topic.rstrip("/")
            payload_size = len(message.encode("utf-8"))
            log(f"Publishing to '{clean_topic}' | Size: {payload_size} bytes", level="DEBUG", context=self.clientID)

            result = self._paho_mqtt.publish(clean_topic, message, self.qos, retain=False)

            if result.rc == PahoMQTT.MQTT_ERR_SUCCESS:
                with self._lock:
                    self._pending_messages += 1
                    self._all_sent_event.clear()

            elif result.rc == PahoMQTT.MQTT_ERR_NO_CONN:
                log(f"Publish failed (not connected). Trying to reconnect...", level="WARN", context=self.clientID)
                try:
                    self._paho_mqtt.reconnect()
                    log(f"Reconnect successful, retrying publish...", level="INFO", context=self.clientID)
                    result = self._paho_mqtt.publish(clean_topic, message, self.qos, retain=False)
                    if result.rc == PahoMQTT.MQTT_ERR_SUCCESS:
                        with self._lock:
                            self._pending_messages += 1
                            self._all_sent_event.clear()
                    else:
                        log(f"Retry failed with result code {result.rc}", level="ERROR", context=self.clientID)
                except Exception as e:
                    log(f"Reconnect failed: {e}", level="ERROR", context=self.clientID)

            else:
                log(f"Publish failed with result code {result.rc}", level="ERROR", context=self.clientID)

        except Exception as e:
            log(f"Exception during publish: {e}", level="ERROR", context=self.clientID)

            
    def myOnConnect(self, client, userdata, flags, rc, properties=None):
        if rc == 0:
            log("Successfully connected to broker.", context=self.clientID)
        else:
            log(f"Connection failed with code {rc}", level="ERROR", context=self.clientID)

    def myOnPublish(self, client, userdata, mid):
        log(f"Message published (mid: {mid})", level="DEBUG", context=self.clientID)
        with self._lock:
            self._pending_messages -= 1
            if self._pending_messages == 0:
                self._all_sent_event.set()



