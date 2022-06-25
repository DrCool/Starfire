require 'socket'
require 'fcntl'
include Socket::Constants

serv = Socket.new( AF_INET, SOCK_STREAM, 0 )
sockaddr = Socket.pack_sockaddr_in( 2000, '0.0.0.0' )
serv.bind( sockaddr )
serv.listen(5)

begin # emulate blocking accept
  socket = serv.accept_nonblock
rescue IO::WaitReadable, Errno::EINTR
  IO.select([serv])
  retry
end
# socket is an accepted socket.

socket.write "Hello!"

#socket.write 255.chr + 253.chr + 3.chr +    255.chr + 251.chr + 3.chr
# "\xff\xfd\x03\xff\xfb\x03"

begin
  loop do
    begin
      puts socket.read_nonblock(1)
    rescue Errno::EAGAIN, Errno::ECONNABORTED, Errno::EINTR, Errno::EWOULDBLOCK
      retry
    end
    
  end
rescue
  socket.close
  serv.close
end

