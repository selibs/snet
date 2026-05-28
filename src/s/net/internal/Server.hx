package s.net.internal;

#if (nodejs || sys)
import haxe.Exception;
import haxe.Constraints;
import haxe.io.Bytes;
import s.URI;
import s.net.internal.Socket;
import s.net.internal.Client;

private typedef ClientConstructor = (uri:URI, name:String, ?connect:Bool, ?certificate:Certificate) -> Void;

@:generic
class Server<T:Constructible<ClientConstructor> & Client> extends Client implements s.shortcut.Shortcut {
	final handlers:Array<T> = [];

	public var clients(get, never):Array<T>;

	@:signal function clientOpened(client:T):Void;

	@:signal function clientClosed(client:T):Void;

	public function new(port:Int, name:String = "SERVER", open:Bool = true, ?cert:Certificate) {
		super(new URI(null, false, true, new HostInfo("localhost", port)), name, false, cert);

		local = remote;
		remote = null;

		if (open)
			this.open();
	}

	override inline function connect() {}

	public function open(limit:Int = 10) {
		try {
			if (running)
				throw "Already opened";

			socket = new Socket();
			socket.bind(local);
			socket.listen(limit);
			running = true;
			handleOpened();
			opened();
			process();
		} catch (e) {
			if (running)
				close();
			logger.error("Failed to open: " + e);
		}
	}

	override function send(data:Bytes)
		broadcast(data);

	public function broadcast(data:Bytes, ?exclude:Array<T>)
		try {
			if (!running)
				throw new NetError("Server is not running");
			exclude = exclude ?? [];
			for (client in handlers)
				if (!exclude.contains(client))
					client.send(data);
		} catch (e)
			logger.error("Failed to broadcast data: " + e);

	override function handleOpened()
		logger.debug("Opened");

	override function handleClosed()
		for (client in handlers.iterator())
			client.close();

	override function tick() {
		try {
			var connection = socket.accept();
			if (connection != null) {
				var client = new T(connection.peer.info.toString(), "HANDLER", false, certificate);
				client.socket = connection;
				client.running = true;
				client.local = connection.host.info;
				client.remote = connection.peer.info;
				client.logger.name = 'HANDLER ${client.local} - ${client.remote}';
				try {
					handleClientOpened(client);
				} catch (e)
					logger.error("Failed to handle client: " + e);
			}
		} catch (e)
			if (e.message.toLowerCase().indexOf("interrupted") == -1) {
				logger.error(e.message);
				return false;
			}

		return true;
	}

	function handleClientOpened(client:T) {
		handlers.push(client);
		client.onClosed(() -> handleClientClosed(client));
		clientOpened(client);
		client.process();
	}

	function handleClientClosed(client:T):Void {
		handlers.remove(client);
		clientClosed(client);
	}

	inline function get_clients()
		return handlers.copy();
}
#end
