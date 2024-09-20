# zignition

## Description

Simulator for CAN data over TCP. Each node is a client connected to the TCP server. 
The server emulates the role of the CAN bus, it receives messages from the clients and forwards them to all the other connections.
Currently, each client connection is handled in a separate thread. This might change in the future, 
as another option is to use syscalls like poll() or select() to handle multiple connections in a single thread.

## Usage

### The Bus
In order to fire up the CAN bus/server you can ``zig build run`` in the root directory of the project.
The ``bus.zig`` server will start listening on the default port 8080.

### The Nodes
Build the client nodes with ``cd src`` then ``zig build-exe node.zig``.
This will create the executable ``node`` in the ``src/`` directory, and you can ``./node`` to run it.
The ``node.zig`` reads the configuration file ``node-config.json`` from the ``resources/`` directory, creates 
the nodes and connects them to the server. Currently, the default configuration contains three nodes - two transmitters
amd one receiver. The receiver (ecu) broadcasts a remote frame to indicate that it needs data.
The transmitters (lPosition and rPosition) send data frames to the receiver in response to the remote frame.

### Filtering
Since each transmitter also broadcasts a data frame as response, lPosition and rPosition will receive each other's data.
This is handled by a filtration mechanism. In the default configuration, the receiver (ecu) is the only node that can process data frames.
The other nodes will ignore the data frames they receive.

## Resources 

### Configuration
The ``node-config.json`` file in the ``resources/`` directory is used to specify the nodes and their properties.

### Diagram
The ``can-spec.drawio`` file in the ``resources/`` directory can be loaded in the https://app.diagrams.net/ website.
Its purpose is to clarify and visualise the structure of CAN frames and the protocol specifics overall. 

## TODO

- [x] Create nodes based on a configuration file
- [ ] Fix synchronization issues
- [ ] Enhance error handling 
- [ ] Implement acknowledgement 
