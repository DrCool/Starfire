## Run the server

Type `./lib/socket.rb` to run the server on port 2000.

## Launch a telnet client to connect

In a new window or on a separate computer, type `telnet <address> 2000`.  If you're running on the same computer, type `telnet 
localhost 2000` to connect.  The server can support multiple simultaneous connections (ie, multiple users at once).

## Launch RubyRemote Server
> docker run --read-only -it -p 2200:2200 ruby-server

