package s.net;

#if (nodejs || sys)
import haxe.io.Bytes;
import haxe.io.BytesBuffer;
import s.net.internal.Socket;
#elseif js
import s.net.http.HttpHeader.*;
#end

using StringTools;

class HttpError extends haxe.Exception {}
typedef HttpStatus = s.net.http.HttpStatus;
typedef HttpMethod = haxe.http.HttpMethod;
typedef HttpRequest = s.net.http.HttpRequest;
typedef HttpResponse = s.net.http.HttpResponse;

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

		var data = readResponseData(socket, timeout);
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

	static function readResponseData(socket:Socket, timeout:Float):Bytes {
		var data = new BytesBuffer();
		var buffer = Bytes.alloc(4096);
		var start = Sys.time();
		var result = Bytes.alloc(0);
		while (true) {
			var remaining = timeout - (Sys.time() - start);
			if (remaining <= 0)
				break;
			if (Socket.select([socket], [], [], remaining).read.length == 0)
				break;

			var length = socket.input.readBytes(buffer, 0, buffer.length);
			if (length <= 0)
				break;
			data.addBytes(buffer, 0, length);
			result = data.getBytes();
			if (isCompleteResponse(result))
				break;
		}
		return result;
	}

	static function isCompleteResponse(bytes:Bytes):Bool {
		var raw = bytes.toString();
		var headerEnd = raw.indexOf("\r\n\r\n");
		var separatorLength = 4;
		if (headerEnd == -1) {
			headerEnd = raw.indexOf("\n\n");
			separatorLength = 2;
		}
		if (headerEnd == -1)
			return false;

		var contentLength:Null<Int> = null;
		var chunked = false;
		for (line in raw.substring(0, headerEnd).split("\n")) {
			var sep = line.indexOf(":");
			if (sep == -1)
				continue;
			var name = line.substring(0, sep).trim().toLowerCase();
			var value = line.substr(sep + 1).trim();
			if (name == "content-length")
				contentLength = Std.parseInt(value) ?? 0;
			else if (name == "transfer-encoding" && value.toLowerCase().indexOf("chunked") != -1)
				chunked = true;
		}

		var bodyStart = headerEnd + separatorLength;
		if (contentLength != null)
			return bytes.length >= bodyStart + contentLength;
		if (chunked)
			return raw.indexOf("\r\n0\r\n", bodyStart) != -1 || raw.indexOf("\n0\n", bodyStart) != -1;
		return true;
	}
	#end
}
