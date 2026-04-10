package s.net.ws;

import haxe.io.Bytes;
#if (nodejs || sys)
import haxe.crypto.Base64;
import s.net.Http;
import s.net.internal.Client;
import s.net.ws.WebSocket.OpCode;

using StringTools;

class WebSocketClient extends Client implements s.shortcut.Shortcut {
	var isHandler:Bool = false;

	@:signal function bytes(bytes:Bytes);

	@:signal function text(text:String);

	overload extern public inline function send(text:String)
		sendFrame(Bytes.ofString(text), Text);

	overload extern public override inline function send(data:Bytes)
		sendFrame(data, Binary);

	function ping()
		sendFrame(Bytes.ofString('ping-${Math.random()}'), Ping);

	function sendFrame(data:Bytes, opcode:OpCode)
		super.send(WebSocket.writeFrame(data, opcode, !isHandler, true));

	override function handleOpened() {
		try {
			handshake();
		} catch (e) {
			logger.error('Handshake failed: $e');
			throw e;
		}
	}

	override function handleClosed()
		sendFrame(Bytes.ofString("close"), Close);

	override function receive(data:Bytes) {
		var frame = WebSocket.readFrame(data);
		switch frame.opcode {
			case Text:
				text(frame.data.toString());
			case Binary:
				bytes(frame.data);
			case Close:
				close();
			case Ping:
				sendFrame(frame.data, Pong);
			case Pong:
				null;
			case Continuation:
				null;
		}
	}

	function handshake() {
		var b = Bytes.alloc(16);
		for (i in 0...16)
			b.set(i, Std.random(255));
		var key = Base64.encode(b);

		var resp = Http.customRequest(socket, false, {
			headers: [
				HOST => remote,
				USER_AGENT => "haxe",
				SEC_WEBSOCKET_KEY => key,
				SEC_WEBSOCKET_VERSION => "13",
				UPGRADE => "websocket",
				CONNECTION => "Upgrade",
				PRAGMA => "no-cache",
				CACHE_CONTROL => "no-cache",
				ORIGIN => local
			]
		}, 1.0);

		if (resp == null)
			throw 'No response from ${remote.host}';
		else
			processHandshake(resp, key);
	}

	function processHandshake(resp:HttpResponse, key:String) {
		if (resp.error != null)
			throw resp.error;
		else {
			if (resp.status != 101)
				throw resp.headers.get(X_WEBSOCKET_REJECT_REASON) ?? resp.statusText;
			var secKey = resp.headers.get(SEC_WEBSOCKET_ACCEPT);
			if (secKey != WebSocket.computeKey(key))
				throw "Incorrect 'Sec-WebSocket-Accept' header value";
		}
	}
}
#elseif js
import js.html.WebSocket as Socket;
import s.URI;

class WebSocketClient implements s.shortcut.Shortcut {
	var ws:Socket;
	var logger:Log.Logger = new Log.Logger("CLIENT");

	public var isClosed(default, null):Bool = true;

	/**
		The other side of a connected socket.
	**/
	public var remote(default, null):HostInfo;

	@:signal function bytes(bytes:Bytes);

	@:signal function text(text:String);

	@:signal function opened();

	@:signal function closed();

	public function new(uri:URI, connect:Bool = true) {
		if (uri == null)
			throw new NetError('Invalid URI');

		if (!["ws", "wss"].contains(uri.proto))
			throw new NetError('Invalid protocol: ${uri.proto}');

		remote = uri.host;

		if (connect)
			this.connect();
	}

	public function connect() {
		if (!isClosed)
			throw new NetError("Already connected");
		ws = new Socket('ws://$remote');
		ws.onerror = e -> {
			logger.error(haxe.Json.stringify(e));
			js.Browser.console.error(e);
			throw e;
		}
		ws.onopen = () -> {
			isClosed = false;
			ws.onmessage = m -> text(m.data);
			ws.onclose = () -> {
				isClosed = true;
				closed();
			}
			logger.name = 'CLIENT $remote';
			logger.debug("Connected");
			opened();
		}
	}

	public function close() {
		ws.close();
		ws.onclose = () -> {
			isClosed = true;
			closed();
		}
	}

	overload extern public inline function send(text:String) {
		if (isClosed)
			throw new NetError("Not connected");
		ws.send(text);
		logger.info('Sent ${Bytes.ofString(text).length} bytes of data');
	}

	overload extern public inline function send(data:Bytes)
		ws.send(data.getData());

	function toString()
		return logger.name;
}
#end
