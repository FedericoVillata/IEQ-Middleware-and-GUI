import json, queue, threading
import paho.mqtt.client as mqtt

class SuggestionSubscriber:
    def __init__(self, cfg, store):
        self.base_topic = cfg["base_topic"]
        self.store = store
        self.cli = mqtt.Client(client_id="suggestion_logger")
        self.cli.on_connect = self._on_conn
        self.cli.on_message = self._on_msg
        self.cli.connect(cfg["messageBroker"], cfg["brokerPort"])
        self.q = queue.Queue()
        threading.Thread(target=self._worker, daemon=True).start()

    def start(self):
        self.cli.loop_start()

    # -------- internal methods (PRIVATE methods) ----------
    def _on_conn(self, client, userdata, flags, rc, properties=None):
        pat = f"{self.base_topic}/+/+"
        client.subscribe(pat, qos=2)
        print("MQTT connected, subscribed to", pat)

    def _on_msg(self, client, userdata, msg):
        self.q.put(msg)   # decoupling IO→worker

    def _worker(self):
        while True:
            msg = self.q.get()
            try:
                apt_id = msg.topic.split("/")[1] # apartment_id
                typ = msg.topic.split("/")[2]
                payload = json.loads(msg.payload)
                evt = payload["e"][0]          
                ts = evt.get("t", 0)
                n_field = evt["n"] # to get room_id and suugetsion_id
                text = evt["v"]

                if typ == "tenant_suggestion":
                    room, sugg_id = n_field.split("/")
                    self.store.add_tenant(apt_id, room, ts, sugg_id, text)

                elif typ == "technical_suggestion":
                    sugg_id = n_field          # direttamente id
                    self.store.add_technical(apt_id, ts, sugg_id, text)

                elif typ == "alert":
                    room = n_field             # room (or room/sensor)
                    self.store.add_alert(apt_id, room, ts, text)

            except Exception as e:
                print("Error parsing message:", e)
            finally:
                self.q.task_done()
