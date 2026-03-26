package s.net.tcp;

#if (nodejs || sys)
typedef TCPClient = s.net.internal.Client;
#end
