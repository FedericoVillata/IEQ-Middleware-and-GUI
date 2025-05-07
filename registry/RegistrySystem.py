import json
import cherrypy
import time
import requests
import threading
import paho.mqtt.client as PahoMQTT
import datetime
from pathlib import Path
from timezonefinder import TimezoneFinder

P = Path(__file__).parent.absolute()
CATALOG = P / 'catalog.json'
SETTINGS = P / 'settings.json'
INDEX = P / 'index.html'
MAXDELAY_DEVICE = 60
MAXDELAY_SERVICE = 60

def CORS():
    cherrypy.response.headers["Access-Control-Allow-Origin"] = "*"
    cherrypy.response.headers["Access-Control-Allow-Methods"] = "GET, POST, PUT, DELETE, OPTIONS"
    cherrypy.response.headers["Access-Control-Allow-Headers"] = "Content-Type"

    if cherrypy.request.method == "OPTIONS":
        cherrypy.response.status = 200
        cherrypy.response.body = b""
        cherrypy.serving.request.handled = True


"""Catalog class that interacts with the catalog.json file"""
class Catalog(object):
    def __init__(self):
        self.filename_catalog = CATALOG
        self.load_file()
    
    def load_file(self):
        for i in range(10):
            try:
                with open(self.filename_catalog, "r") as fs:                
                    self.catalog = json.loads(fs.read())
                return            
            except Exception:
                print("Problem in loading catalog")

    def write_catalog(self):
        """Write data on catalog json file."""
        with open(self.filename_catalog, "w") as fs:
            json.dump(self.catalog, fs, ensure_ascii=False, indent=2)
            fs.write("\n")

    def add_device(self, device_json, user):
        self.load_file()
        flag = 0
        for dev in self.catalog["devices"]:
            if dev["deviceID"] == device_json["deviceID"]:
                flag = 1
        if flag == 0:
            device_res_json = {
                "deviceID": device_json["deviceID"],
                "Services": device_json["Services"],
                "lastUpdate": time.time()
            }
            self.catalog["devices"].append(device_res_json)
        self.write_catalog()

    def add_service(self, service_json , user):
        self.load_file()
        flag = 0
        for service in self.catalog["services"]:
            if service["serviceID"] == service_json["serviceID"]:
                flag = 1
        if flag == 0:
            service_res_json = {
                "serviceID": service_json["serviceID"],
                "lastUpdate": time.time()
            }
            self.catalog["services"].append(service_res_json)
        self.write_catalog()

    def add_user(self, user_json):
        self.load_file()
        found = 0
        for user in self.catalog["users"]:
            if user["userId"] == user_json["userId"]:
                found = 1
        if found == 0:
            user_json = {
                "userId": user_json["userId"],
                "password": user_json["password"],
                "permissions": user_json["permission"],
                "apartments": []
            }
            self.catalog["users"].append(user_json)
            self.write_catalog()
            return "Added user"
        else:
            return "User already exists"

    def remove_user(self, userId):
        self.load_file()
        found = 0
        index = 0
        for user in self.catalog["users"]:
            if user["userId"] == userId:
                found = 1
                for apt in user["apartments"]:
                    self.removeFromApartments(apt, userId)
                del self.catalog["users"][index]
                self.write_catalog()
            index += 1
        if found == 0:
            return "User not found"
    
    def find_smallest_missing_apartmentId(self):
    # Extract the numeric part of apartmentIds
        self.load_file()
        numbers = set()
        for apt in self.catalog["apartments"]:
            apt_id = apt.get("apartmentId", "")
            if apt_id.startswith("apartment"):
                try:
                    num = int(apt_id[9:])  # Extract integer part
                    numbers.add(num)
                except ValueError:
                    pass  # Ignore invalid cases
        i = 0
        while i in numbers:
            i += 1
        return f"apartment{i}"      
    def add_suggestion(self, suggestion_json):
        self.load_file()
        suggestion = {
            "suggestionId": self.find_smallest_missing_suggestionId(),
            "suggestionName": suggestion_json["suggestionName"],
            "text": suggestion_json["text"]
        }
        self.catalog["tenant_suggestions"].append(suggestion)
        for apt in self.catalog["apartments"]:
            for room in apt["rooms"]:
                room["suggestions"].append({
                    "suggestionId": suggestion["suggestionId"],
                    "state": 1
                })
        self.write_catalog()
        return "done"
    def update_suggestion(self, suggestion_json):
        self.load_file()
        found = 0
        for suggestion in self.catalog["tenant_suggestions"]:
            if suggestion["suggestionId"] == suggestion_json["suggestionId"]:
                found = 1
                suggestion["text"] = suggestion_json["text"]
                for apt in self.catalog["apartments"]:
                    for room in apt["rooms"]:
                        for s in room["suggestions"]:
                            if s["suggestionId"] == suggestion_json["suggestionId"]:
                                s["text"] = suggestion_json["text"]
                self.write_catalog()
        if found == 0:
            return "Suggestion not found"
        else:  
            return "done"
    def activate_suggestion(self, suggestionId, apartmentId, roomId):
        self.load_file()
        found = 0
        for apt in self.catalog["apartments"]:
            if apt["apartmentId"] == apartmentId:
                found = 1
                for room in apt["rooms"]:
                    for s in room["suggestions"]:
                        if s["suggestionId"] == suggestionId:
                            s["state"] = 1
                            self.write_catalog()
                            return "done"
        if found == 0:
            return "Apartment not found"
    def deactivate_suggestion(self, suggestionId, apartmentId, roomId):
        self.load_file()
        found = 0
        for apt in self.catalog["apartments"]:
            if apt["apartmentId"] == apartmentId:
                found = 1
                for room in apt["rooms"]:
                    for s in room["suggestions"]:
                        if s["suggestionId"] == suggestionId:
                            s["state"] = 0
                            self.write_catalog()
                            return "done"
        if found == 0:
            return "Apartment not found"
    def remove_suggestion(self, suggestionId):
        self.load_file()
        found = 0
        for suggestion in self.catalog["tenant_suggestions"]:
            if suggestion["suggestionId"] == suggestionId:
                found = 1
                self.catalog["tenant_suggestions"].remove(suggestion)
                for apt in self.catalog["apartments"]:
                    for room in apt["rooms"]:
                        for s in room["suggestions"]:
                            if s["suggestionId"] == suggestionId:
                                room["suggestions"].remove(s)
                self.write_catalog()
        if found == 0:
            return "Suggestion not found"
        else:  
            return "done"
    def find_smallest_missing_suggestionId(self):
        self.load_file()
        numbers = set()
        for s in self.catalog["tenant_suggestions"]:
            s_id = s.get("suggestionId", "")
            if s_id.startswith("S"):
                try:
                    num = int(s_id[1:])  # Extract integer part
                    numbers.add(num)
                except ValueError:
                    pass  # Ignore invalid cases
        i = 0
        while i in numbers:
            i += 1
        return f"S{i}" 
        
    def add_apartment(self, adaptor_url, apt_json):

        updated_rooms = []
        suggestions = []
        for s in self.catalog["tenant_suggestions"]:
            suggestions.append({
                "suggestionId": s["suggestionId"],
                "state": 1
            })
        for room in apt_json["rooms"]:
            updated_sensors = [{"sensorId": sensor["sensorId"], "measurements": sensor["measurements"], "lastUpdate": 0} for sensor in room["sensors"]]
            updated_rooms.append({
                "roomId": room["roomId"],
                "sensors": updated_sensors,
                "suggestions": suggestions
            })
        aptId = self.find_smallest_missing_apartmentId()
        tf = TimezoneFinder()
        coord = apt_json["coordinates"]
        timezone_str = tf.timezone_at(lng=coord["long"], lat=coord["lat"])
        timezone_str = timezone_str or "Europe/Rome"
        timezone_str 
        apt_res ={
            "users": [apt_json["userId"]],
            "apartmentId": aptId,
            "apartmentName": apt_json["apartmentName"],
            "type": apt_json["type"],
            "coordinates": apt_json["coordinates"],
            "timezone": timezone_str,
            "MAC": apt_json["MAC"],
            "rooms": updated_rooms,
            "settings": self.catalog["base_settings"]
        }
        headers = {'content-type': 'application/json; charset=UTF-8'}
        response = requests.post(adaptor_url + "/addApartment", data=json.dumps(apt_res), headers=headers)
        response = {"status": "OK", "code": 200, "message": "Data processed"}
        self.add_apartment2user(apt_json["userId"], apt_res["apartmentId"])
        self.load_file()
        self.catalog["apartments"].append(apt_res)
        self.write_catalog()
        return "done"
    
    def add_apartment2user(self, userId, apartmentId):
        """Add a new apartment to a user."""
        self.load_file()
        found = 0
        for user in self.catalog["users"]:
            if user["userId"] == userId:
                found = 1
                if apartmentId not in user["apartments"]:
                    user["apartments"].append(apartmentId)
                    self.write_catalog()
                    return "Apartment added"
                else:
                    return "Apartment already registered"
        if found == 0:
            return "User not found"
        
    def add_user2apartment(self, userId, apartmentId):
        """Add a new user to an apartment."""
        self.load_file()
        found = 0
        for apt in self.catalog["apartments"]:
            if apt["apartmentId"] == apartmentId:
                found = 1
                if userId not in apt["users"]:
                    apt["users"].append(userId)
                    self.write_catalog()
                    self.add_apartment2user(userId, apartmentId)                    
                    return "User added"
                else:
                    return "User already registered"
        if found == 0:
            return "Apartment not found"

    def removeFromApartments(self, apartmentId, userId):
        """Remove the apartment also into catalog['plants']"""
        for apt in self.catalog["apartments"]:
            if apt["apartmentId"] == apartmentId:
                apt["users"].remove(userId)

    def remove_apartment(self, apartmentId):
        self.load_file()
        for apt in self.catalog["apartments"]:
            if apt["apartmentId"] == apartmentId:
                for user in apt["users"]:
                    self.removeFromUsers(user, apartmentId)
                self.catalog["apartments"].remove(apt)
                self.write_catalog()
                return "Apartment removed"
        return "Apartment not found"

    def removeFromUsers(self, userId, apartmentId):
        """Remove the user also into catalog['users']"""
        for user in self.catalog["users"]:
            if user["userId"] == userId:
                user["apartments"].remove(apartmentId)
                if len(user["apartments"]) == 0:
                    self.catalog["users"].remove(user)
                self.write_catalog()
                return "User removed"

    def update_device(self, deviceJson):
        """Update timestamp of a devices."""
        self.load_file()
        found = 0
        for dev in self.catalog['devices']:
            if dev['deviceID'] == deviceJson["n"]:
                found = 1
                print("Updating %s timestamp." % dev['deviceID'])
                dev['lastUpdate'] = deviceJson["t"]    
        if not found:# Insert again the device
            print("not found")
            device_json = {
                "deviceID": deviceJson["n"],
                "netType": deviceJson["u"],
                "route": deviceJson["v"],
                "lastUpdate": deviceJson["t"]
            }
            self.catalog["devices"].append(device_json)
        self.write_catalog()

    def update_service(self, serviceJson):
        """Update timestamp of a services."""
        self.load_file()
        found = 0
        for service in self.catalog['services']:
            if service['serviceID'] == serviceJson["n"]:
                found = 1
                print("Updating %s timestamp." % service['serviceID'])
                service['lastUpdate'] = serviceJson["t"]    
        if not found:# Insert again the device
            print("not found")
            service_json = {
                "serviceID": serviceJson["n"],
                "netType": serviceJson["u"],
                "route": serviceJson["v"],
                "lastUpdate": serviceJson["t"]
            }
            self.catalog["services"].append(service_json)
        self.write_catalog()
    def modify_settings(self, apt, body):
        """Modify the thresholds of an apartment."""
        
        for key, value in body["settings"].items():
            if key in apt["settings"]:
                if isinstance(apt["settings"][key], dict) and isinstance(value, dict):
                    for sub_key, sub_value in value.items():
                        if sub_key in apt["settings"][key]:
                            apt["settings"][key][sub_key] = sub_value  
                elif isinstance(value, (int, float, str, bool)):
                    apt["settings"][key] = value  
        return apt
        
    def reset_settings(self, apt):
        """Reset the thresholds of an apartment."""
        self.load_file()
        apt["settings"] = self.catalog["base_settings"]
        self.write_catalog()
            
    def update_tokens(self, body):
        """
        Update tokens of a Netatmo Gateway.
        """
        self.load_file() 
        found = False

        # Iterate through the apartments in the catalog
        for apt in self.catalog["apartments"]:
            # Check if the apartment matches the provided apartmentId
            if apt["apartmentId"] == body["apartmentId"]:
                # Iterate through the MAC array to find the matching gateway
                for gateway in apt["MAC"]:
                    if gateway["name"] == "netatmo" and gateway["MAC"] == body["gatewayMAC"]:
                        # Update the tokens for the Netatmo gateway
                        gateway["accessToken"] = body["accessToken"]
                        gateway["refreshToken"] = body["refreshToken"]
                        found = True
                        break

            # If the gateway was found and updated, exit the loop
            if found:
                break

        # Write the updated catalog back to storage
        if found:
            self.write_catalog()
            return "done"
        else:
            return "Apartment not found"

    
    def remove_old_device(self):
        """Remove old devices whose timestamp is expired."""
        self.load_file()
        removable = []
        for counter, d in enumerate(self.catalog['devices']):
            if time.time() - float(d['lastUpdate']) > MAXDELAY_DEVICE:
                print("Removing... %s" % (d['deviceID']))
                removable.append(counter)
        for index in sorted(removable, reverse=True):
                del self.catalog['devices'][index]
        self.write_catalog()
        
    def remove_old_service(self):
        """Remove old services whose timestamp is expired."""
        self.load_file()
        removable = []
        for counter, s in enumerate(self.catalog['services']):
            if time.time() - float(s['lastUpdate']) > MAXDELAY_SERVICE:
                print("Removing... %s" % (s['serviceID']))
                removable.append(counter)
        for index in sorted(removable, reverse=True):
                del self.catalog['services'][index]
        self.write_catalog()
    def login(self, body):
        """Login user."""
        self.load_file()
        found = 0
        for user in self.catalog["users"]:
            if user["userId"] == body["userId"]:
                found = 1
                if user["password"] == body["password"]:
                    return user['permissions']
                else:
                    return "Invalid password"
        if found == 0:
            return "User not found"
class Webserver(object):

    @cherrypy.expose
    def OPTIONS(self, *args, **kwargs):
        cherrypy.response.headers["Access-Control-Allow-Origin"] = "*"
        cherrypy.response.headers["Access-Control-Allow-Methods"] = "GET, POST, PUT, DELETE, OPTIONS"
        cherrypy.response.headers["Access-Control-Allow-Headers"] = "Content-Type"
        cherrypy.response.status = 200
        return ""
    
    """CherryPy webserver."""
    exposed = True
    def start(self):
        conf={
            '/':{
            'request.dispatch':cherrypy.dispatch.MethodDispatcher(),
            'tools.sessions.on':True,
            'tools.CORS.on': True
            }
        }
        cherrypy.tree.mount(self,'/',conf)
        cherrypy.config.update({'server.socket_port':8081})
        cherrypy.config.update({'server.socket_host':'0.0.0.0'})
        cherrypy.tools.CORS = cherrypy.Tool('before_handler', CORS)
        cherrypy.engine.start()
        try:
            with open(SETTINGS, "r") as fs:                
                self.settings = json.loads(fs.read())   
            self.cat = Catalog()
        except Exception:
            print("Problem in loading settings")

    def GET(self, *uri, **params):
        self.cat.load_file()
        if len(uri) == 0:
            return open(INDEX)
        else:
            #GET Devices from catalog            
            if uri[0] == 'devices':
                return json.dumps(self.cat.catalog["devices"])
            #GET Services from catalog    
            if uri[0] == 'services':
                return json.dumps(self.cat.catalog["services"])
            #GET Users from catalog    
            if uri[0] == 'users':
                out = [] #users without password
                for user in self.cat.catalog["users"]:
                    out.append({
                        "userId": user["userId"], 
                        "permissions": user["permissions"],
                        "apartments": user["apartments"]})
                return json.dumps(out)
            #GET Apartments from catalog    
            if uri[0] == 'apartments':
                if len(uri) > 1:
                    for apt in self.cat.catalog["apartments"]:
                        if apt["apartmentId"] == uri[1]:
                            return json.dumps(apt)
                    return json.dumps({"status": "NOT_OK", "code": 400, "message": "Apartment not found"})
                else:
                    return json.dumps(self.cat.catalog["apartments"])
            #GET Default settings from catalog 
            if uri[0] == "base_settings":
                return json.dumps(self.cat.catalog["base_settings"])
            #GET whole catalog 
            if uri[0] == "catalog":
                return json.dumps(self.cat.catalog)
            
        

    def POST(self, *uri, **params):
        """Define POST HTTP method for RESTful webserver.Modify content of catalogs"""  
        
        self.cat.load_file()
        if uri[0] == 'add_device':
            # Add new device.
            body = json.loads(cherrypy.request.body.read())  # Read body data
            self.cat.add_device(body, uri[1])#(device, user)
            return 200
        
        if uri[0] == 'add_service':
            # Add new service.
            body = json.loads(cherrypy.request.body.read())  # Read body data
            self.cat.add_service(body, uri[1])
            return 200
        if uri[0] == 'add_user':
            # Add new user.
            body = json.loads(cherrypy.request.body.read())  # Read body {userid, password}
            out = self.cat.add_user(body)
            if out == "User already registered":
                response = {"status": "NOT_OK",
                            "code": 400}
                #raise cherrypy.HTTPError("400", "User already registered")
                return json.dumps(response)
            else:          
                response = {"status": "OK", "code": 200}
                return json.dumps(response)
        if uri[0] == 'update_tokens':
            body = json.loads(cherrypy.request.body.read())  # Read body {userid, password}
            out = self.cat.update_tokens(body)
            if out == "done":
                response = {"status": "OK", "code": 200}
                return json.dumps(response)
            else:
                response = {"status": "NOT_OK", "code": 400}    
                return json.dumps(response)
                
        if uri[0] == 'add_apt':
            # Add new apartment.
            body = json.loads(cherrypy.request.body.read())  # Read body data
            print(f"adding this apt {body}" )
            out = self.cat.add_apartment(self.settings["adaptor_url"], body)
            if out == "Apartment already registered":
                response = {"status": "NOT_OK", "code": 400, "message": "Plant already registered"}
                return json.dumps(response)
            elif out == "User not found":
                response = {"status": "NOT_OK", "code": 400, "message": "User not found"}
                return json.dumps(response)
            elif out == "done":
                response = {"status": "OK", "code": 200, "message": "Plant registered successfully"}
                return json.dumps(response)
            #elif out == "Invalid plant code":
            #    response = {"status": "NOT_OK", "code": 400, "message": "Invalid plant code"}
            #    return json.dumps(response)
        if uri[0] == 'add_user_to_apartment':
            # Add user to apartment.
            body = json.loads(cherrypy.request.body.read())  # Read body data
            out = self.cat.add_user2apartment(body["userId"], body["apartmentId"])
            if out == "User already registered":
                response = {"status": "NOT_OK", "code": 400, "message": "User already registered"}
                return json.dumps(response)
            elif out == "User not found":   
                response = {"status": "NOT_OK", "code": 400, "message": "User not found"}
                return json.dumps(response) 
            elif out == "Apartment not found":
                response = {"status": "NOT_OK", "code": 400, "message": "Apartment not found"}
                return json.dumps(response)
            else:
                response = {"status": "OK", "code": 200, "message": "Data processed"}
                return json.dumps(response)
        if uri[0] == 'login':
            # Login user.
            body = json.loads(cherrypy.request.body.read())
            out = self.cat.login(body)
            if out == "User not found":
                response = {"status": "NOT_OK", "code": 400, "message": "User not found"}
                return json.dumps(response)
            elif out == "Invalid password":
                response = {"status": "NOT_OK", "code": 400, "message": "Invalid password"}
                return json.dumps(response)
            else:
                response = {"status": "OK", "code": 200, "message": out}
                return json.dumps(response)
        if uri[0] == 'add_suggestion':
            # Add suggestion.
            body = json.loads(cherrypy.request.body.read())
            out = self.cat.add_suggestion(body)
            response = {"status": "OK", "code": 200, "message": "Data processed"}
            return json.dumps(response)
            

    def PUT(self, *uri, **params):
        self.cat.load_file()
        
        if uri[0] == 'update_suggestion':
            #Update suggestion data
            body = json.loads(cherrypy.request.body.read())
            out = self.cat.update_suggestion(body)
            if out == "Suggestion not found":
                response = {"status": "NOT_OK", "code": 400, "message": "Invalid suggestion ID"}
            else:
                response = {"status": "OK", "code": 200, "message": "Data updated successfully"}
            return json.dumps(response)

        elif uri[0] == 'mod_apartment':
            #Update apartment data
            body = json.loads(cherrypy.request.body.read())  # Read body data
            apartmentId = body["apartmentId"]
            newapartmentId = body["new_name"]
            found = False
            for apt in self.cat.catalog["apartments"]:
                if apt["apartmentId"] == apartmentId:
                    found = True
                    index = self.cat.catalog["apartments"].index(plant)
            self.cat.catalog['apartments'][index]['apartmentId'] = newapartmentId 
            self.cat.write_catalog()
            if not found:   
                response = {"status": "NOT_OK", "code": 400, "message": "Invalid apartment ID"}
            else:
                response = {"status": "OK", "code": 200, "message": "Data updated successfully"}
            return json.dumps(response)
        elif uri[0] == 'update_sensors':
            #Update sensors data
            body = json.loads(cherrypy.request.body.read())
            self.cat.load_file()
            apartmentId = body["apartmentId"]
            found = False
            for apartment in self.cat.catalog["apartments"]:
                if apartment["apartmentId"] == apartmentId:
                    found = True
                    for point in body["points"]:
                        mac = point["tags"]["MAC"]
                        timestamp = point["time"]
                        for room in apartment["rooms"]:
                            for sensor in room["sensors"]:
                                if sensor["sensorId"] == mac:
                                    sensor["lastUpdate"] = datetime.datetime.utcfromtimestamp(timestamp / 1e9).isoformat() + "Z"
            if not found:
                response = {"status": "NOT_OK", "code": 400, "message": "Invalid apartment ID"}
            else:
                self.cat.write_catalog()
                response = {"status": "OK", "code": 200, "message": "Data updated successfully"}
        elif uri[0] == 'modify_settings':
            body = json.loads(cherrypy.request.body.read())  # Read body data
            apartmentId = body["apartmentId"]
            found = False
            for apt in self.cat.catalog["apartments"]:
                if apt["apartmentId"] == apartmentId:
                    found = True
                    apt = self.cat.modify_settings(apt, body)
                    self.cat.write_catalog()
            if not found:   
                response = {"status": "NOT_OK", "code": 400, "message": "Invalid apartment ID"}
            else:
                response = {"status": "OK", "code": 200, "message": "Data updated successfully"}
            return json.dumps(response)
        elif uri[0] == 'reset_settings':
            body = json.loads(cherrypy.request.body.read())
            apartmentId = body["apartmentId"]
            found = False
            self.cat.load_file()
            for apt in self.cat.catalog["apartments"]:
                if apt["apartmentId"] == apartmentId:
                    found = True
                    apt["settings"] = self.cat.catalog["base_settings"]
                    self.cat.write_catalog()
            if not found:   
                response = {"status": "NOT_OK", "code": 400, "message": "Invalid apartment ID"}
            else:
                response = {"status": "OK", "code": 200, "message": "Data updated successfully"}
            return json.dumps(response)
        elif uri[0] == 'activate_suggestion':
            #Activate suggestion
            body = json.loads(cherrypy.request.body.read())
            out = self.cat.activate_suggestion(body["suggestionId"], body["apartmentId"], body["roomId"])
            if out == "Apartment not found":
                response = {"status": "NOT_OK", "code": 400, "message": "Invalid apartment ID"}
            else:
                response = {"status": "OK", "code": 200, "message": "Data updated successfully"}
            return json.dumps(response)
        elif uri[0] == 'deactivate_suggestion':
            #Deactivate suggestion
            body = json.loads(cherrypy.request.body.read())
            out = self.cat.deactivate_suggestion(body["suggestionId"], body["apartmentId"], body["roomId"])
            if out == "Apartment not found":
                response = {"status": "NOT_OK", "code": 400, "message": "Invalid apartment ID"}
            else:
                response = {"status": "OK", "code": 200, "message": "Data updated successfully"}
            return json.dumps(response)
        """elif uri[0] == 'setreportfrequency':
            #Update the frequency of the report
            body = json.loads(cherrypy.request.body.read())  # Read body data
            plantCode = body['plantCode']
            reportf = body['report_frequency']
            found = False
            for plant in self.cat.catalog['plants']:
                if plant['plantCode'] == plantCode:
                    found = True
                    plant['report_frequency'] = reportf
                    self.cat.write_catalog()
            if found:
                response = {"status": "OK", "code": 200, "message": "Data updated successfully"}
            else:
                response = {"status": "NOT_OK", "code": 400, "message": "Invalid plant code"}        
            return json.dumps(response) 
        elif uri[0] == "transferuser":
            #Update chatID for telegram 
            body = json.loads(cherrypy.request.body.read())
            found = False
            for user in self.cat.catalog['users']:
                if user['userId'] == body['userId']:
                    found = True
                    user['chatID'] = body['chatID']
                    self.cat.write_catalog()
            if found:
                response = {"status": "OK", "code": 200, "message": "Data updated successfully"}
            else:
                response = {"status": "NOT_OK", "code": 400, "message": "Invalid plant code"}   
            return json.dumps(response) """
            
    def DELETE(self, *uri, **params):
        if uri[0] == 'del_user':
            out = self.cat.remove_user(uri[1])
            if out == "User not found":
                response = {"status": "NOT_OK","code": 400}
                return json.dumps(response)
            else:
                response = {"status": "OK", "code": 200}
                return json.dumps(response)           
        elif uri[0] == 'del_apt':
            out = self.cat.remove_apartment(uri[1])
            response = requests.delete(self.settings["adaptor_url"] + "/deleteApartment/" + uri[1])
            response = {"status": "OK", "code": 200}
            if out == "User not found":
                raise cherrypy.HTTPError("400", "user not found")
            if out == "Apartment not found":
                raise cherrypy.HTTPError("400", "plant not found")
            else:
                result = {"status": "OK", "code": 200, "message": "Data processed"}
                return json.dumps(result)
        elif uri[0] == 'del_suggestion':
            suggestionId = uri[1] 
            out = self.cat.remove_suggestion(suggestionId)
            if out == "Suggestion not found":
                response = {"status": "NOT_OK", "code": 400, "message": "Invalid suggestion ID"}
            else:
                response = {"status": "OK", "code": 200, "message": "Data deleted successfully"}
            return json.dumps(response)


class MySubscriber:
        def __init__(self, clientID, topic, broker, port):
            self.clientID = clientID
			# create an instance of paho.mqtt.client
            self._paho_mqtt = PahoMQTT.Client(clientID, False) 
            
			# register the callback
            self._paho_mqtt.on_connect = self.myOnConnect
            self._paho_mqtt.on_message = self.myOnMessageReceived 
            self.topic = topic
            self.messageBroker = broker
            self.port = port

        def start (self):
            #manage connection to broker
            self._paho_mqtt.connect(self.messageBroker, self.port)
            self._paho_mqtt.loop_start()
            # subscribe for a topic
            self._paho_mqtt.subscribe(self.topic, 2)

        def stop (self):
            self._paho_mqtt.unsubscribe(self.topic)
            self._paho_mqtt.loop_stop()
            self._paho_mqtt.disconnect()

        def myOnConnect (self, paho_mqtt, userdata, flags, rc):
            print ("Connected to %s with result code: %d" % (self.messageBroker, rc))

        def myOnMessageReceived (self, paho_mqtt , userdata, msg):
            #Listening to all messages with topic "RootyPy/#"
            message = json.loads(msg.payload.decode("utf-8")) #{"bn": updateCatalog<>, "e": [{...}]}
            catalog = Catalog()
            if message['bn'] == "updateCatalogDevice":            
                catalog.update_device(message['e'][0])# {"n": PlantCode/deviceName, "t": time.time(), "v": "", "u": IP}
            if message['bn'] == "updateCatalogService":            
                catalog.update_service(message['e'][0])# {"n": serviceName, "t": time.time(), "v": "", "u": IP}


# Threads
class First(threading.Thread):
    """Thread to run CherryPy webserver."""
    exposed=True
    def __init__(self, ThreadID, name):
        """Initialise thread widh ID and name."""
        threading.Thread.__init__(self)
        self.ThreadID = ThreadID
        self.name = name
        self.webserver = Webserver()
        self.webserver.start()
        

class Second(threading.Thread):
    """MQTT Thread."""

    def __init__(self, ThreadID, name):
        """Initialise thread widh ID and name."""
        threading.Thread.__init__(self)
        self.ThreadID = ThreadID
        self.name = name
        with open(SETTINGS, 'r') as file:
            data = json.load(file)
        self.topic = data["base_topic"]
        self.broker = data["broker"]
        self.mqtt_port = int(data["port"])

    def run(self):
        """Run thread."""
        cat = Catalog()
        cat.load_file()
        sub = MySubscriber("registry_sub", self.topic, self.broker, self.mqtt_port)
        sub.loop_flag = 1
        sub.start()

        while sub.loop_flag:
            time.sleep(1)

        while True:
            time.sleep(1)

        sub.stop()

class Third(threading.Thread):
    """Old device remover thread.
    Remove old devices which do not send alive messages anymore.
    Devices are removed every five minutes.
    """

    def __init__(self, ThreadID, name):
        """Initialise thread widh ID and name."""
        threading.Thread.__init__(self)
        self.ThreadID = ThreadID
        self.name = name

    def run(self):
        """Run thread."""
        time.sleep(MAXDELAY_DEVICE+1)
        while True:
            cat = Catalog()
            cat.remove_old_device()
            time.sleep(MAXDELAY_DEVICE+1)
            
class Fourth(threading.Thread):
    """Old service remover thread.
    Remove old services which do not send alive messages anymore.
    Services are removed every five minutes.
    """

    def __init__(self, ThreadID, name):
        """Initialise thread widh ID and name."""
        threading.Thread.__init__(self)
        self.ThreadID = ThreadID
        self.name = name

    def run(self):
        """Run thread."""
        time.sleep(MAXDELAY_SERVICE+1)
        while True:
            cat = Catalog()
            cat.remove_old_service()
            time.sleep(MAXDELAY_SERVICE+1)

#Main

def main():
    """Start all threads."""
    thread1 = First(1, "CherryPy")
    print("> Starting CherryPy...")
    thread1.start()
"""     thread2 = Second(2, "Updater")
    thread3 = Third(3, "RemoverDevices")
    thread4 = Fourth(4, "RemoverServices")

    time.sleep(1)
    print("\n> Starting MQTT device updater...")
    thread2.start()

    time.sleep(1)
    print("\n> Starting Device remover...\nDelete old devices every %d seconds."% MAXDELAY_DEVICE)
    thread3.start()
    
    time.sleep(1)
    print("\n> Starting Service remover...\nDelete old devices every %d seconds."% MAXDELAY_SERVICE)
    thread4.start() """

if __name__ == '__main__':
    main()
