package s.net.internal;

#if (nodejs || sys)
import haxe.io.Bytes;
import s.net.Certificate;
import s.net.NetError;
import s.net.internal.Socket;
import s.URI;
import s.URI.HostInfo;

class Client implements s.shortcut.Shortcut {
	var socket:Socket;
	final logger:Log.Logger;

	public final secure:Bool;
	public final certificate:Certificate;

	public var running(default, null):Bool = false;

	/**
		Absolute uri of a client
	**/
	public var uri(default, null):URI;

	/**
		Local side of a client.
	**/
	public var local(default, null):HostInfo;

	/**
		Remote side of a client.
	**/
	public var remote(default, null):HostInfo;

	@:signal function opened();

	@:signal function closed();

	@:signal function data(data:Bytes);

	public function new(uri:URI, name:String = "CLIENT", connect:Bool = true, ?certificate:Certificate):Void {
		if (uri == null)
			throw new NetError("Invalid URI");

		this.uri = uri;
		this.certificate = certificate;

		remote = uri.host;
		secure = uri.secure;
		logger = new Log.Logger(name ?? remote.toString());

		if (connect)
			this.connect();
	}

	public function connect() {
		try {
			if (running)
				throw new NetError("Already connected");
			socket = new Socket();
			socket.connect(remote);
			running = true;
			local = socket.host.info;
			handleOpened();
			opened();
			process();
		} catch (e) {
			if (running)
				close();
			logger.error("Failed to connect: " + e);
		}
	}

	public function close()
		try {
			if (!running)
				throw new NetError("Not connected");
			running = false;
			socket.close();
		} catch (e)
			logger.error("Failed to close: " + e);

	public function send(data:Bytes)
		try {
			if (!running)
				throw new NetError("Not connected");
			socket.send(data);
		} catch (e)
			logger.error("Failed to send data: " + e);

	function handleOpened()
		logger.debug("Connected");

	function handleClosed()
		logger.debug("Closed");

	function process() {
		#if target.threaded
		sys.thread.Thread.create(() -> {
		#end
			while (running && tick())
				Sys.sleep(0.01);
		#if target.threaded
		});
		#end
		handleClosed();
		if (running)
			close();
		closed();
	}

	function tick():Bool {
		try {
			var data = socket.read();
			if (data != null) {
				if (data.length > 0)
					receive(data);
				return true;
			} else
				logger.debug("Connection closed by peer");
		} catch (e)
			logger.error("Failed to tick: " + e);
		return false;
	}

	function receive(data:Bytes)
		this.data(data);

	function toString()
		return logger.name;
}
#end
