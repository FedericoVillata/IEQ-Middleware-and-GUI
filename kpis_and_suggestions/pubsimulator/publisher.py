class MyPublisher:
    def __init__(self, module_name, topic):
        self.module_name = module_name
        self.topic = topic

    def start(self):
        print(f"[{self.module_name}] Publisher started on topic '{self.topic}'")

    def myPublish(self, message, topic):
        print(f"\n📤 PUBLISH to {topic}:\n{message}")

    def stop(self):
        print(f"[{self.module_name}] Publisher stopped.")
