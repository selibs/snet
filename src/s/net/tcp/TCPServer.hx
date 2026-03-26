package s.net.tcp;

#if (nodejs || sys)
typedef TCPServer = s.net.internal.Server<TCPClient>;
#end
