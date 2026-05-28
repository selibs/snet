package s.net.http;

#if (nodejs || sys)
import sys.io.File;
import sys.FileSystem;
import haxe.io.Path;
import haxe.io.Bytes;
import haxe.io.BytesBuffer;
import s.net.internal.Socket;
import s.net.internal.Client;

using StringTools;

@:nullSafety
typedef ServerConfig = {
	location:String,
	statics:Array<String>
}

@:access(s.net.internal.Client)
abstract class HttpServer extends s.net.internal.Server<Client> {
	public var config:ServerConfig;

	public function new(port:Int, ?config:ServerConfig, limit:Int = 10, open:Bool = true, name:String = "SERVER", ?cert:Certificate) {
		super(port, name, false, cert);
		this.config = config ?? {location: ".", statics: []};
		if (open)
			this.open(limit);
	}

	override function handleClientOpened(client:Client) {
		logger.debug('Accepted ${client.remote}');
		try {
			var data = readRequestData(client, 2.0);
			if (data == null || data.length == 0) {
				logger.warning('No request data from ${client.remote}');
				client.close();
				return;
			}

			var req:HttpRequest = data;
			var resp = processRawRequest(req);
			if (resp == null)
				resp = {status: InternalServerError, statusText: "Internal Server Error"};
			if (!resp.headers.exists(CONNECTION))
				resp.headers.set(CONNECTION, "close");

			if (req != null)
				logger.log('<- ${req.method} ${req.path}');
			else
				logger.warning("<- <invalid request>");
			logResponse(resp);
			client.send(resp);
		} catch (e)
			logger.error(Std.string(e));

		client.close();
	}

	function readRequestData(client:Client, timeout:Float):Bytes {
		var data = new BytesBuffer();
		var buffer = Bytes.alloc(4096);
		var start = Sys.time();
		var result = Bytes.alloc(0);
		try {
			while (true) {
				var remaining = timeout - (Sys.time() - start);
				if (remaining <= 0)
					break;
				if (Socket.select([client.socket], [], [], remaining).read.length == 0)
					break;

				var length = client.socket.input.readBytes(buffer, 0, buffer.length);
				if (length <= 0)
					break;
				data.addBytes(buffer, 0, length);
				result = data.getBytes();
				if (isCompleteRequest(result))
					break;
			}
		} catch (e) {
			if (Std.string(e).toLowerCase().indexOf("eof") == -1)
				throw e;
		}
		return result;
	}

	function isCompleteRequest(bytes:Bytes):Bool {
		var raw = bytes.toString();
		var headerEnd = raw.indexOf("\r\n\r\n");
		var separatorLength = 4;
		if (headerEnd == -1) {
			headerEnd = raw.indexOf("\n\n");
			separatorLength = 2;
		}
		if (headerEnd == -1)
			return false;

		var contentLength = 0;
		for (line in raw.substring(0, headerEnd).split("\n")) {
			var sep = line.indexOf(":");
			if (sep == -1)
				continue;
			if (line.substring(0, sep).trim().toLowerCase() == "content-length") {
				contentLength = Std.parseInt(line.substr(sep + 1).trim()) ?? 0;
				break;
			}
		}
		return bytes.length >= headerEnd + separatorLength + contentLength;
	}

	abstract function processRequest(req:HttpRequest):HttpResponse;

	function processRawRequest(req:HttpRequest):HttpResponse {
		if (req != null) {
			switch req.method {
				case Get:
					switch req.path {
						case "/":
							return loadStatic("/index.html");
						case var s if (matchesStaticPath(s) || staticFileExists(s)):
							return loadStatic(s);
						default:
							return processRequest(req);
					}
				default:
					return processRequest(req);
			}
		}
		return {status: BadRequest, statusText: "Bad Request"}
	}

	function logResponse(resp:HttpResponse) {
		var msg = '   -> ${resp.status} ${resp.statusText}';
		if ((resp.status : Int) < 200)
			logger.info(msg);
		else if ((resp.status : Int) < 300)
			logger.debug(msg);
		else if ((resp.status : Int) < 400)
			logger.warning(msg);
		else if ((resp.status : Int) < 500)
			logger.error(msg);
		else
			logger.fatal(msg);
	}

	function matchesStaticPath(path:String):Bool {
		for (pattern in config.statics)
			if (pattern.endsWith("/*")) {
				var prefix = pattern.substr(0, pattern.length - 1);
				if (path.startsWith(prefix))
					return true;
			} else if (path == pattern)
				return true;
		return false;
	}

	function staticFileExists(path:String):Bool {
		var path = resolveStaticPath(path);
		return path != null && FileSystem.exists(path) && !FileSystem.isDirectory(path);
	}

	function resolveStaticPath(path:String):String {
		if (path == null || path == "" || path.indexOf("\x00") != -1)
			return null;

		path = path.urlDecode().replace("\\", "/");
		while (path.startsWith("/"))
			path = path.substr(1);

		var parts = [];
		for (part in path.split("/")) {
			if (part == "" || part == ".")
				continue;
			if (part == "..")
				return null;
			parts.push(part);
		}

		if (parts.length == 0)
			return null;
		return config.location + "/" + parts.join("/");
	}

	function loadStatic(path:String):HttpResponse {
		path = resolveStaticPath(path);

		if (path == null || !FileSystem.exists(path) || FileSystem.isDirectory(path))
			return {status: NotFound, statusText: "Not Found"}

		try {
			var bytes = File.getBytes(path);
			var ext = Path.extension(path);
			switch ext {
				case "js":
					return {data: bytes.toString(), headers: [CONTENT_TYPE => "application/javascript; charset=utf-8"]}
				case "css":
					return {data: bytes.toString(), headers: [CONTENT_TYPE => "text/css; charset=utf-8"]}
				case "html":
					return {data: bytes.toString(), headers: [CONTENT_TYPE => "text/html; charset=utf-8"]}
				case "json":
					return {data: bytes.toString(), headers: [CONTENT_TYPE => "application/json"]}
				case "png", "gif", "jpg", "jpeg":
					return {bytes: bytes, headers: [CONTENT_TYPE => 'image/$ext']}
				default:
					return {bytes: bytes, headers: [CONTENT_TYPE => "application/octet-stream"]}
			}
		} catch (e)
			return {status: InternalServerError, statusText: "Internal Server Error"}
	}
}
#end
