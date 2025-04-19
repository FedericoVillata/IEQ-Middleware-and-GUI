# publisher_service.py
import time
import json


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
        {"n": f"pmv_kpis/{room_id}/value", "u": "arb", "t": timestamp, "v": metrics.get("pmv")},
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
        print(f"\n Publishing event: {event['n']} to topic: {topic}")
        print(json.dumps(payload, indent=2))
        publisher.myPublish(json.dumps(payload), topic)


def publish_tenant_suggestions(publisher, base_topic, apartment_id, room_id, suggestions):
    if not suggestions:
        return

    topic = f"{base_topic}/{apartment_id}/tenant_suggestion"
    timestamp = time.time()

    for metric, tip in suggestions.items():
        event = {
            "bn": topic,
            "e": [{
                "n": f"{room_id}/{metric}",
                "t": timestamp,
                "u": "string",
                "v": tip
            }]
        }
        print(f"\n Publishing tenant suggestion for {metric} in {room_id}: {tip}")
        publisher.myPublish(json.dumps(event), topic)


def publish_technical_suggestions(publisher, base_topic, apartment_id, room_id, suggestions):
    if not suggestions:
        return

    topic = f"{base_topic}/{apartment_id}/technical_suggestion"
    timestamp = time.time()

    for key, tip in suggestions.items():
        event = {
            "bn": topic,
            "e": [{
                "n": f"{room_id}/{key}",
                "t": timestamp,
                "u": "string",
                "v": tip
            }]
        }
        print(f"\n Publishing technical suggestion for {key} in {room_id}: {tip}")
        publisher.myPublish(json.dumps(event), topic)


def publish_alerts(publisher, base_topic, apartment_id, room_id, classifications):
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
            print(f"\n Alert for {room_id} - {metric}: {label}")
            publisher.myPublish(json.dumps(alert_event), topic)


# --- MQTT Publisher Class ---
import paho.mqtt.client as PahoMQTT

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

    def start(self):
        try:
            self._paho_mqtt.connect(self.messageBroker, self.port)
            self._paho_mqtt.loop_start()
            print(f"[{self.clientID}] Connecting to MQTT broker at {self.messageBroker}:{self.port}")
        except Exception as e:
            print(f"[{self.clientID}] Failed to connect to MQTT broker: {e}")

    def stop(self):
        self._paho_mqtt.loop_stop()
        self._paho_mqtt.disconnect()
        print(f"[{self.clientID}] Disconnected from MQTT broker.")

    def myPublish(self, message, topic):
        try:
            # Ensure topic does not end with a slash (to avoid mismatches)
            clean_topic = topic.rstrip("/")

            # Log message size in bytes
            payload_size = len(message.encode("utf-8"))
            print(f"[{self.clientID}] Publishing to topic '{clean_topic}' | Payload size: {payload_size} bytes")

            result = self._paho_mqtt.publish(clean_topic, message, self.qos, retain=False)

            if result.rc != PahoMQTT.MQTT_ERR_SUCCESS:
                print(f"[{self.clientID}] Publish failed with result code {result.rc}")
        except Exception as e:
            print(f"[{self.clientID}] Exception during publish: {e}")

    def myOnConnect(self, client, userdata, flags, rc, properties=None):
        if rc == 0:
            print(f"[{self.clientID}] Successfully connected to broker.")
        else:
            print(f"[{self.clientID}] Connection failed with code {rc}")

    def myOnPublish(self, client, userdata, mid):
        print(f"[{self.clientID}] Message published with mid: {mid}")

