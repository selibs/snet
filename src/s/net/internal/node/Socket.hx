package s.net.internal.node;

#if nodejs
import haxe.io.Bytes;
import js.node.Net;
import js.node.Buffer;
import js.node.net.Server;
import js.node.net.Socket as NodeSocket;

class Socket {
	static var connections:Array<Socket> = [];

	public static function select(read:Array<Socket>, write:Array<Socket>, others:Array<Socket>,
			?timeout:Float):{read:Array<Socket>, write:Array<Socket>, others:Array<Socket>} {
		var ret = {read: [], write: [], others: []}
		for (c in connections)
			if (read.indexOf(c) != -1 && c.input.hasData == true)
				ret.read.push(c);
		if (write != null)
			ret.write = write.copy();
		if (others != null)
			ret.others = others.copy();

		return ret;
	}

	var newConnections:Array<Socket> = [];
	var socket(default, null):NodeSocket;
	var server:Server;
	var boundHost:String;
	var boundPort:Int;

	public var input(default, null):SocketInput;
	public var output(default, null):SocketOutput;

	public function new() {}

	function setSocket(s:NodeSocket) {
		socket = s;
		socket.on("error", error -> trace('Node socket error: ${Std.string(error)}'));
		input = new SocketInput(this);
		output = new SocketOutput(this);
	}

	function acceptConnection(socket:NodeSocket) {
		socket.setTimeout(0);
		var nodeSocket = new Socket();
		nodeSocket.setSocket(socket);
		connections.push(nodeSocket);
		newConnections.push(nodeSocket);
	}

	public function accept() {
		if (newConnections.length == 0)
			throw "Blocking";
		return newConnections.pop();
	}

	public function listen(connections:Int):Void {
		if (server == null)
			throw "You must bind the Socket to an address";
		server.listen({host: boundHost, port: boundPort, backlog: connections});
	}

	public function bind(host:String, port:Int):Void {
		this.boundHost = host;
		this.boundPort = port;
		if (server == null) {
			server = Net.createServer(socket -> acceptConnection(socket));
			server.on("error", error -> trace('Node server error: ${Std.string(error)}'));
		}
	}

	public function connect(host:String, port:Int):Void {
		boundHost = host;
		boundPort = port;
		if (socket == null) {
			socket = new NodeSocket();
			socket.on("error", error -> trace('Node client socket error: ${Std.string(error)}'));
			input = new SocketInput(this);
			output = new SocketOutput(this);
		}
		socket.connect(port, host);
	}

	public function host():{host:String, port:Int} {
		if (socket != null && socket.localAddress != null)
			return {host: socket.localAddress, port: socket.localPort};
		return {host: boundHost, port: boundPort};
	}

	public function peer():{host:String, port:Int} {
		if (socket == null || socket.remoteAddress == null)
			return {host: "0.0.0.0", port: 0};
		return {host: socket.remoteAddress, port: socket.remotePort};
	}

	public function setBlocking(blocking:Bool) {}

	public function setTimeout(timeout:Int) {}

	public function close() {
		server?.close();
		socket?.destroy();
	}
}

@:access(s.net.internal.node.Socket)
class SocketInput {
	var socket:Socket;
	var buffer:Buffer = null;

	public var hasData = false;

	public function new(socket:Socket) {
		this.socket = socket;
		this.socket.socket.on("data", onData);
	}

	function onData(data:Any) {
		var a = [];
		if (buffer != null)
			a.push(buffer);
		a.push(Buffer.from(data));
		buffer = Buffer.concat(a);
		hasData = true;
	}

	public function readBytes(s:Bytes, pos:Int, len:Int):Int {
		if (buffer == null)
			return 0;
		var n = buffer.length;
		if (n > len)
			n = len;
		if (len > n)
			len = n;
		var part = buffer.slice(0, len);
		var remain = null;
		if (buffer.length > len)
			remain = buffer.slice(len);
		var src = part.hxToBytes();
		s.blit(pos, src, 0, len);
		hasData = (remain != null);
		buffer = remain;
		return n;
	}
}

@:access(s.net.internal.node.Socket)
class SocketOutput {
	var socket:Socket;
	var buffer:Buffer = null;

	public function new(socket:Socket) {
		this.socket = socket;
	}

	public function write(data:Bytes) {
		var a = [];
		if (buffer != null)
			a.push(buffer);
		a.push(Buffer.hxFromBytes(data));
		buffer = Buffer.concat(a);
	}

	public function flush() {
		this.socket.socket.write(buffer);
		buffer = null;
	}
}
#end
