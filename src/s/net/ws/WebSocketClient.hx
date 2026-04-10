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

	override function handleOpened()
		try {
			handshake();
		} catch (e) {
			logger.error('Handshake failed: $e');
			throw e;
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
				USER_AGENT => "s",
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
import js.html.WebSocket as WS;
import s.URI;

class WebSocketClient implements s.shortcut.Shortcut {
	var ws:WS;
	final logger:Log.Logger;

	public var running(default, null):Bool = false;

	/**
		The other side of a connected socket.
	**/
	public var remote(default, null):HostInfo;

	@:signal function bytes(bytes:Bytes);

	@:signal function text(text:String);

	@:signal function opened();

	@:signal function closed();

	public function new(uri:URI, name:String = "CLIENT", connect:Bool = true) {
		if (uri == null)
			throw new NetError('Invalid URI');

		remote = uri.host;
		logger = new Log.Logger(name ?? remote.toString());

		if (connect)
			this.connect();
	}

	public function connect() {
		try {
			if (running)
				throw new NetError("Already connected");
			ws = new WS('ws://$remote');
			ws.onopen = () -> {
				running = true;
				handleOpened();
				opened();
			}
			ws.onclose = () -> {
				running = false;
				handleClosed();
				closed();
			}
			ws.onmessage = m -> text(m.data);
			ws.onerror = e -> logger.error(haxe.Json.stringify(e));
		} catch (e) {
			if (running)
				close();
			logger.error("Failed to connect: " + e);
		}
	}

	public function close()
		ws.close();

	overload extern public inline function send(text:String)
		try {
			if (!running)
				throw new NetError("Not connected");
			ws.send(text);
		} catch (e)
			logger.error("Failed to send data: " + e);

	overload extern public inline function send(data:Bytes)
		try {
			if (!running)
				throw new NetError("Not connected");
			ws.send(data.getData());
		} catch (e)
			logger.error("Failed to send data: " + e);

	function handleOpened()
		logger.debug("Connected");

	function handleClosed()
		logger.debug("Closed");

	function toString()
		return logger.name;
}
#end
