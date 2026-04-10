package s.net;

typedef Certificate = {
	?host:String,
	cert:sys.ssl.Certificate,
	key:sys.ssl.Key,
	verify:Bool
}
