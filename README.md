# zignition

## Description

Simulator for CAN data over TCP. Each node is a client connected to the TCP server. 
The server emulates the role of the CAN bus, it receives messages from the clients and forwards them to all the other connections.
Currently, each client connection is handled in a separate thread. This might chane in the future, 
as another option is to use syscalls like poll() or select() to handle multiple connections in a single thread.

## Usage

### The Bus
In order to fire up the CAN bus/server you can ``zig build run`` in the root directory of the project.
The ``bus.zig`` server will start listening on the default port 8080.

### The Nodes
Build the client nodes with ``cd src`` then ``zig build-exe node.zig``.
This will create the executable ``node`` in the ``src/`` directory and you can ``./node`` to run it.
The ``node.zig`` automatically creates two client nodes in separate threads, connects them to the bus/server,
client1 sends a remote frame to indicate its need for data from client2, client2 responds with a data frame.

## Resources 

The ``can-spec.drawio`` file in the ``resources/`` directory can be loaded in the https://app.diagrams.net/ website.
Its purpose is to clarify and visualise the structure of CAN frames and the protocol specifics overall. 

## TODO

- [x] Create nodes based on a configuration file
- [ ] Enhance error handling 
- [ ] Implement acknowledgement 