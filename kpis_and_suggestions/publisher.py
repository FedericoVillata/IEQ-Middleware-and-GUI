from pathlib import Path
import paho.mqtt.client as PahoMQTT
import json
import time

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
