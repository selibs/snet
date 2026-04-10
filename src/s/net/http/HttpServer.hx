package s.net.http;

#if (nodejs || sys)
import sys.io.File;
import sys.FileSystem;
import haxe.io.Path;
import haxe.io.Bytes;
import s.net.internal.Socket;
import s.net.internal.Client;

using StringTools;

@:nullSafety
typedef ServerConfig = {
	location:String,
	statics:Array<String>
}

abstract class HttpServer extends s.net.internal.Server<Client> {
	public var config:ServerConfig;

	public function new(uri:URI, limit:Int = 10, open:Bool = true, name:String = "SERVER", ?cert:Certificate, ?config:ServerConfig) {
		super(uri, limit, open, name, cert);
		this.config = config;
	}

	override function handleClientOpened(client:Client) {
		var callback = (data:Bytes) -> {
			try {
				var req:Request = data;
				var resp = processRawRequest(req);
				logger.log('<- ${req.method} ${req.path}');
				var msg = '   -> ${resp.status} ${resp.statusText}';
				if ((resp.status : Int) < 200)
					logger.info(msg);
				else if ((resp.status : Int) < 300)
					logger.debug(msg);
				else if ((resp.status : Int) < 400)
					logger.warning(msg);
				else if ((resp.status : Int) < 400)
					logger.error(msg);
				else
					logger.fatal(msg);
				client.send(resp);
			} catch (e)
				logger.error(e.message);
		};
		client.onData(callback);
		client.onClosed(() -> client.offData(callback));
		
		super.handleClientOpened(client);
	}

	abstract function processRequest(req:Request):Response;

	function processRawRequest(req:Request):Response {
		if (req != null) {
			switch req.method {
				case Get:
					switch req.path {
						case "/":
							return loadStatic("/index.html");
						case var s if (matchesStaticPath(s)):
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

	function loadStatic(path:String):Response {
		path = config.location + path;

		if (!FileSystem.exists(path))
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
