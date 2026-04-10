package s.net.ws;

#if (nodejs || sys)
import s.net.Http;
import s.net.internal.Server;

using StringTools;

@:access(s.net.ws.WebSocketClient)
class WebSocketServer extends Server<WebSocketClient> {
	overload extern public inline function send(text:String):Void
		broadcast(text);

	overload extern public inline function broadcast(text:String, ?exclude:Array<WebSocketClient>):Void
		if (running) {
			exclude = exclude ?? [];
			for (client in clients)
				if (!exclude.contains(client))
					client.send(text);
		} else
			logger.error("Failed to broadcast data: server is not open");

	override function handleClientOpened(client:WebSocketClient) {
		var data = client.socket.read(1);

		if (data == null || data.length == 0) {
			logger.error("Failed to handle client: No handshake data received from " + client.remote);
			client.close();
			return;
		}

		var resp:HttpResponse = {};
		var accepted = false;

		if (data != null) {
			var req:HttpRequest = data;
			resp.headers.set(SEC_WEBSOCKET_VERSION, "13");
			if (req.method != "GET" || req.version != "HTTP/1.1") {
				resp.status = 400;
				resp.statusText = "Bad";
				resp.headers.set(CONNECTION, "close");
				resp.headers.set(X_WEBSOCKET_REJECT_REASON, 'Bad request');
			} else if (req.headers.get(SEC_WEBSOCKET_VERSION) != "13") {
				resp.status = 426;
				resp.statusText = "Upgrade";
				resp.headers.set(CONNECTION, "close");
				resp.headers.set(X_WEBSOCKET_REJECT_REASON,
					'Unsupported websocket client version: ${req.headers.get(SEC_WEBSOCKET_VERSION)}, Only version 13 is supported.');
			} else if (req.headers.get(UPGRADE)?.toLowerCase() != "websocket") {
				resp.status = 426;
				resp.statusText = "Upgrade";
				resp.headers.set(CONNECTION, "close");
				resp.headers.set(X_WEBSOCKET_REJECT_REASON, 'Unsupported upgrade header: ${req.headers.get(UPGRADE)}.');
			} else if ((req.headers.get(CONNECTION) ?? "").toLowerCase().indexOf("upgrade") == -1) {
				resp.status = 426;
				resp.statusText = "Upgrade";
				resp.headers.set(CONNECTION, "close");
				resp.headers.set(X_WEBSOCKET_REJECT_REASON, 'Unsupported connection header: ${req.headers.get(CONNECTION)}.');
			} else {
				var key = req.headers.get(SEC_WEBSOCKET_KEY);
				resp.status = 101;
				resp.statusText = "Switching Protocols";
				resp.headers.set(UPGRADE, "websocket");
				resp.headers.set(CONNECTION, "Upgrade");
				resp.headers.set(SEC_WEBSOCKET_ACCEPT, WebSocket.computeKey(key));
				accepted = true;
			}
		} else
			resp = {status: BadRequest, statusText: "Bad Request"}

		client.socket.send(resp);
		
		if (!accepted) {
			client.close();
			return;
		}

		client.isHandler = true;
		super.handleClientOpened(client);
	}
}
#end
