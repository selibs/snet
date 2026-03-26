package s;

import haxe.ds.StringMap;

using StringTools;

@:forward()
abstract URI(URIData) from URIData to URIData {
	static function schemeSeparatorIndex(value:String):Int {
		var index = value.indexOf(":");
		if (index <= 0)
			return -1;

		var pathIndex = value.indexOf("/");
		if (pathIndex >= 0 && pathIndex < index)
			return -1;

		return isValidScheme(value.substring(0, index)) ? index : -1;
	}

	static function defaultPortForScheme(value:String):Int
		return switch value {
			case "http", "ws": 80;
			case "https", "wss": 443;
			case _: null;
		}

	static function isValidScheme(value:String):Bool
		return ~/^[A-Za-z][A-Za-z0-9+\-.]*$/.match(value);

	@:from
	public static function fromString(source:String):URI {
		if (source == null)
			return null;

		var proto:String = null;
		var hasAuthority = false;
		var host:HostInfo = null;
		var user:String = null;
		var pass:String = null;
		var path = "";
		var query:URIQuery = null;
		var fragment:String = null;

		var fragmentIndex = source.indexOf("#");
		if (fragmentIndex >= 0) {
			fragment = source.substr(fragmentIndex + 1);
			source = source.substring(0, fragmentIndex);
		}

		var queryIndex = source.indexOf("?");
		if (queryIndex >= 0) {
			query = source.substr(queryIndex + 1);
			source = source.substring(0, queryIndex);
		}

		var schemeIndex = schemeSeparatorIndex(source);
		if (schemeIndex >= 0) {
			proto = source.substring(0, schemeIndex).toLowerCase();
			source = source.substr(schemeIndex + 1);
		}

		if (source.startsWith("//")) {
			hasAuthority = true;
			source = source.substr(2);

			var authorityEnd = source.indexOf("/");
			if (authorityEnd < 0)
				authorityEnd = source.length;

			var authority = source.substring(0, authorityEnd);
			path = authorityEnd < source.length ? source.substr(authorityEnd) : "";

			var userInfoEnd = authority.lastIndexOf("@");
			var hostInfo = authority;
			if (userInfoEnd >= 0) {
				hostInfo = authority.substr(userInfoEnd + 1);
				var userInfo = authority.substring(0, userInfoEnd);
				var passwordIndex = userInfo.indexOf(":");
				if (passwordIndex >= 0) {
					user = userInfo.substring(0, passwordIndex);
					pass = userInfo.substr(passwordIndex + 1);
				} else
					user = userInfo;
			}
			host = HostInfo.fromString(hostInfo);
			if (host == null && hostInfo != "")
				return null;
		} else
			path = source;

		var isSecure = proto == "https" || proto == "wss";
		var defaultPort = defaultPortForScheme(proto);
		if (host != null && host.host != "" && host.port == null && defaultPort != null)
			host = new HostInfo(host.host, defaultPort, false);

		return new URI(proto, isSecure, hasAuthority, host, user, pass, path, query, fragment);
	}

	public function new(proto:String, ?isSecure:Bool, ?hasAuthority:Bool, ?host:HostInfo, ?user:String, ?pass:String, ?path:String, ?query:URIQuery,
			?fragment:String) {
		this = {
			proto: proto,
			isSecure: isSecure == true,
			hasAuthority: hasAuthority ?? (host != null || user != null || pass != null),
			host: host,
			user: user,
			pass: pass,
			path: path,
			query: query,
			fragment: fragment
		}
	}

	@:to
	public function toString():String {
		var str = "";

		if (this.proto != null)
			str += '${this.proto}:';

		if (this.hasAuthority == true)
			str += "//";

		if (this.user != null) {
			str += this.user;
			if (this.pass != null)
				str += ':${this.pass}';
			str += '@';
		}

		if (this.host != null)
			str += this.host;
		str += this.path ?? "";
		if (this.query != null)
			str += '?${this.query.toString()}';

		if (this.fragment != null)
			str += '#${this.fragment}';

		return str;
	}
}

@:structInit
private class URIData {
	public var proto:String;
	public var isSecure:Bool = false;
	public var hasAuthority:Bool = false;
	public var host:HostInfo = null;
	public var user:String = null;
	public var pass:String = null;
	public var path:String = null;
	public var query:URIQuery = null;
	public var fragment:String = null;
}

abstract URIQuery(URIQueryData) from URIQueryData to URIQueryData {
	@:from
	public static function fromString(value:String):URIQuery {
		if (value == null)
			return null;

		var query = new URIQuery();
		if (value == "")
			return query;

		for (part in value.split("&")) {
			var separatorIndex = part.indexOf("=");
			if (separatorIndex >= 0)
				query.set(part.substring(0, separatorIndex), part.substr(separatorIndex + 1));
			else
				query.set(part, null);
		}
		return query;
	}

	public function new() {
		this = {map: new StringMap(), order: []}
	}

	@:arrayAccess
	public inline function get(key:String):String
		return this.map.get(key);

	@:arrayAccess
	public inline function setItem(key:String, value:String):String {
		set(key, value);
		return value;
	}

	public inline function exists(key:String):Bool
		return this.map.exists(key);

	public function set(key:String, value:String):Void {
		if (!this.map.exists(key))
			this.order.push(key);
		this.map.set(key, value);
	}

	public function remove(key:String):Bool {
		if (!this.map.remove(key))
			return false;
		this.order.remove(key);
		return true;
	}

	public inline function keys():Iterator<String>
		return this.order.iterator();

	public inline function iterator():Iterator<String>
		return this.map.iterator();

	@:to
	public function toString():String {
		var parts = [];
		for (key in this.order) {
			var value = this.map.get(key);
			parts.push(value == null ? key : '$key=$value');
		}
		return parts.join("&");
	}
}

private typedef URIQueryData = {
	map:StringMap<String>,
	order:Array<String>
}

@:forward()
abstract HostInfo(HostInfoData) from HostInfoData to HostInfoData {
	@:from
	public static function fromString(value:String):HostInfo {
		if (value == null)
			return null;

		if (value == "")
			return new HostInfo("", null);

		var host = value;
		var port:Int = null;
		var explicitPort = false;

		if (value.startsWith("[")) {
			var closeIndex = value.indexOf("]");
			if (closeIndex < 0)
				return null;

			host = value.substring(0, closeIndex + 1);
			var suffix = value.substr(closeIndex + 1);
			if (suffix != "") {
				if (!suffix.startsWith(":"))
					return null;
				var portString = suffix.substr(1);
				if (!isPort(portString))
					return null;
				port = Std.parseInt(portString);
				explicitPort = true;
			}
		} else {
			var firstColon = value.indexOf(":");
			var lastColon = value.lastIndexOf(":");
			if (firstColon >= 0 && firstColon == lastColon) {
				var portString = value.substr(lastColon + 1);
				if (isPort(portString)) {
					host = value.substring(0, lastColon);
					port = Std.parseInt(portString);
					explicitPort = true;
				}
			}
		}

		return new HostInfo(host, port, explicitPort);
	}

	public function new(host:String, port:Int, ?explicitPort:Bool) {
		this = {host: host, port: port, explicitPort: explicitPort != false}
	}

	@:to
	public inline function toString():String {
		var str = this.host;
		if (this.port != null && this.explicitPort != false)
			str += ':${this.port}';
		return str;
	}

	static function isPort(value:String):Bool
		return value != "" && ~/^\d+$/.match(value);
}

private typedef HostInfoData = {
	host:String,
	port:Int,
	?explicitPort:Bool
}
