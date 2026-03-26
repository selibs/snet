package s.net;

import s.URI;

@:forward()
abstract Proxy(ProxyData) from ProxyData to ProxyData {
	@:from
	public static function fromString(value:String):Proxy {
		var reg = new EReg("^(?:(?P<user>[^:@]+)(?::(?P<pass>[^@]*))?@)?([^/?#]+)$", "i");
		if (value == null || !reg.match(value))
			return null;

		return {
			host: reg.matched(3),
			auth: reg.matched(1) != null ? {
				user: reg.matched(1),
				pass: reg.matched(2)
			} : null
		};
	}

	@:to
	public function toString():String {
		var str = "";

		if (this.auth != null && this.auth.user != null) {
			str += this.auth.user;
			if (this.auth.pass != null)
				str += ':${this.auth.pass}';
			str += '@';
		}

		str += this.host;
		return str;
	}
}

private typedef ProxyData = {
	host:HostInfo,
	?auth:{
		user:String,
		?pass:String
	}
}
