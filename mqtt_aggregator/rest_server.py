import cherrypy, json
from store_service import DailyStore
from functools import wraps

def cors():
    cherrypy.response.headers.update({
        "Access-Control-Allow-Origin": "*",
        "Access-Control-Allow-Methods": "GET, OPTIONS",
        "Access-Control-Allow-Headers": "Content-Type"
    })
    if cherrypy.request.method == "OPTIONS":
        cherrypy.response.status = 200
        return b""

def safe(fn):
    @wraps(fn)
    def wrapper(*a, **kw):
        try:
            return fn(*a, **kw)
        except cherrypy.HTTPError:
            raise
        except Exception as ex:
            raise cherrypy.HTTPError(500, str(ex))
    return wrapper

class API:
    exposed = True
    def __init__(self, store: DailyStore):
        self.s = store

    @safe
    def GET(self, *uri, **params):
        """
        Return the whole JSON file.

        Example response:
        {
            "apartment3": {
                "tenant": {
                    "1C": [
                        {
                            "ts": 1746981092.54,
                            "id": "S17",
                            "text": "Many people might feel uncomfortable..."
                        }
                    ],
                    ...
                },
                "technical": [
                    {
                        "ts": 1746981095.51,
                        "id": "_DEBUG_TEST_ALWAYS_TRIGGERED",
                        "text": "Debug: this is a fake suggestion..."
                    }
                ],
                "alerts": {
                    "1C": [
                        {
                            "ts": 1746981101.89,
                            "text": "ppd_class classified as R"
                        }
                    ],
                    ...
                }
            },
            ...
        }

        Usage: GET /all
        """
        if uri and uri[0] == "all":
            return json.dumps(self.s.data)
        raise cherrypy.HTTPError(404, "Only /all is supported")



def run_rest(store: DailyStore, port: int = 8090):
    conf = {
        "/": {
            "request.dispatch": cherrypy.dispatch.MethodDispatcher(),
            "tools.CORS.on": True
        }
    }
    cherrypy.tools.CORS = cherrypy.Tool("before_handler", cors)
    cherrypy.tree.mount(API(store), "/", conf)
    cherrypy.config.update({"server.socket_host": "0.0.0.0",
                            "server.socket_port": port})
    cherrypy.engine.start()
