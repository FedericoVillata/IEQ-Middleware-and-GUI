import paho.mqtt.client as mqtt

class MyPublisher:
    def __init__(self, module_name, topic, broker="localhost", port=1883):
        self.module_name = module_name
        self.topic = topic
        self.client = mqtt.Client()
        self.broker = broker
        self.port = port

    def start(self):
        self.client.connect(self.broker, self.port)
        self.client.loop_start()
        print(f"[{self.module_name}] Connected to MQTT broker at {self.broker}:{self.port} on topic '{self.topic}'")

    def myPublish(self, message, topic):
        self.client.publish(topic, payload=message)
        print(f"📤 Published to {topic}:\n{message}")

    def stop(self):
        self.client.loop_stop()
        self.client.disconnect()
        print(f"[{self.module_name}] Disconnected from MQTT broker.")
