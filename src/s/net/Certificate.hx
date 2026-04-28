package s.net;

#if (nodejs || sys)
typedef Certificate = {
	?host:String,
	cert:sys.ssl.Certificate,
	key:sys.ssl.Key,
	verify:Bool
}
#end
