package s.net;

#if (nodejs || sys)
import s.net.internal.Socket;
#elseif js
import s.net.http.Header.*;
#end

using StringTools;

class HttpError extends haxe.Exception {}
typedef HttpStatus = s.net.http.Status;
typedef HttpMethod = haxe.http.HttpMethod;
typedef HttpRequest = s.net.http.Request;
typedef HttpResponse = s.net.http.Response;

class Http {
	#if (nodejs || sys)
	public static function request(uri:URI, ?req:HttpRequest, ?proxy:Proxy, timeout:Float = 1.0, ?cert:Certificate) @:privateAccess
	#elseif js
	public static function request(uri:URI, ?req:HttpRequest, ?proxy:Proxy, timeout:Float = 1.0)
	#end
	{
		if (uri == null)
			throw new HttpError('Invalid URI');
		req = req ?? {};
		#if (nodejs || sys)
		if (!req.headers.exists(HOST))
			req.headers.set(HOST, uri.host.host);
		var socket = new Socket();

		if (proxy != null)
			socket.connect(proxy.host);
		else
			socket.connect(uri.host);
		return customRequest(socket, true, req, timeout);
		#elseif js
		var url = uri.toString();
		if (req.path != null && req.path != "" && req.path != "/") {
			if (url.endsWith("/") && req.path.startsWith("/"))
				url += req.path.substr(1);
			else if (!url.endsWith("/") && !req.path.startsWith("/"))
				url += "/" + req.path;
			else
				url += req.path;
		}

		var method = req.method ?? Get;
		var query = [];
		for (p in req.params.keys())
			query.push(StringTools.urlEncode(p) + "=" + StringTools.urlEncode(req.params.get(p)));
		if (query.length > 0 && method == Get)
			url += (url.indexOf("?") == -1 ? "?" : "&") + query.join("&");

		var hasCookies = req.cookies != null && req.cookies.keys().hasNext();
		var body:Dynamic = null;
		if (req.data != null)
			body = req.data;
		else if (req.bytes != null)
			body = req.bytes.getData();
		else if (method == Post && query.length > 0)
			body = query.join("&");

		function createRequest(useArrayBuffer:Bool) {
			var xhr:js.html.XMLHttpRequest = js.Browser.createXMLHttpRequest();
			xhr.open(method, url, false);

			if (useArrayBuffer) {
				try {
					untyped xhr.responseType = "arraybuffer";
				} catch (_:Dynamic)
					xhr.overrideMimeType("text/plain; charset=x-user-defined");
			} else
				xhr.overrideMimeType("text/plain; charset=x-user-defined");

			if (hasCookies && !req.headers.exists("Cookie")) {
				var pairs = [];
				for (k in req.cookies.keys())
					pairs.push('$k=${req.cookies.get(k)}');
				xhr.setRequestHeader("Cookie", pairs.join("; "));
			}

			for (h in req.headers.keys())
				xhr.setRequestHeader(h, req.headers.get(h));

			if (body != null && method == Post && req.data == null && req.bytes == null && !req.headers.exists(CONTENT_TYPE))
				xhr.setRequestHeader(CONTENT_TYPE, "application/x-www-form-urlencoded");

			return xhr;
		}

		function updateResponseMeta(xhr:js.html.XMLHttpRequest, resp:HttpResponse) {
			resp.status = xhr.status;
			resp.statusText = xhr.statusText;
			resp.headers = [];
			resp.cookies = [];

			var rawHeaders = xhr.getAllResponseHeaders();
			if (rawHeaders != null && rawHeaders != "")
				for (line in rawHeaders.split("\r\n")) {
					var sep = line.indexOf(":");
					if (sep > -1)
						resp.headers.set(line.substr(0, sep), line.substr(sep + 1).trim());
				}
		}

		function updateResponseBytesFromString(text:String, resp:HttpResponse) {
			if (text == null)
				return;

			var bytes = haxe.io.Bytes.alloc(text.length);
			for (i in 0...text.length)
				bytes.set(i, StringTools.fastCodeAt(text, i) & 0xFF);
			resp.bytes = bytes;

			var contentType = resp.headers.get(CONTENT_TYPE);
			if (contentType != null && (contentType.startsWith("text/") || contentType.contains("json")))
				resp.data = text;
		}

		function updateResponseBytesFromText(xhr:js.html.XMLHttpRequest, resp:HttpResponse) {
			var text:String = null;
			try {
				text = xhr.responseText;
			} catch (_:Dynamic) {}

			updateResponseBytesFromString(text, resp);
		}

		function send(xhr:js.html.XMLHttpRequest):Null<String> {
			try {
				xhr.send(body);
				return null;
			} catch (e:Dynamic)
				return Std.string(e);
		}

		var resp:HttpResponse = {
			headers: [],
			cookies: []
		};
		var xhr = createRequest(true);
		var sendError = send(xhr);
		if (sendError != null)
			return ({
				status: 0,
				statusText: "Error",
				error: sendError,
				headers: [],
				cookies: []
			} : HttpResponse);

		updateResponseMeta(xhr, resp);

		var status:Int = resp.status;
		if (200 <= status && status < 400) {
			var response:Dynamic = xhr.response;
			if (Std.isOfType(response, js.lib.ArrayBuffer))
				resp.bytes = haxe.io.Bytes.ofData(cast response);
			else if (Std.isOfType(response, String))
				updateResponseBytesFromString(cast response, resp);
			else {
				xhr = createRequest(false);
				sendError = send(xhr);
				if (sendError != null)
					resp.error = sendError;
				else {
					updateResponseMeta(xhr, resp);
					updateResponseBytesFromText(xhr, resp);
				}
			}
		} else
			resp.error = 'Http Error #$status';

		return resp;
		#end
	}
	#if (nodejs || sys)
	public static function customRequest(socket:Socket, close:Bool, req:HttpRequest, timeout:Float = 1.0) {
		socket.send(req);

		var data = socket.read(timeout);
		var resp:HttpResponse = null;
		if (data.length > 0)
			try {
				resp = data;
			} catch (e)
				resp = {
					status: BadGateway,
					statusText: "Server does not support the request method"
				}
		else
			resp = {
				status: GatewayTimeout,
				statusText: "Timed out waiting for response"
			}
		if (close)
			socket.close();
		return resp;
	}
	#end
}
