# FPGA Webserver

Goals: Use a cheap FPGA to support TCP, and then, use it to serve a blog.

## Geting Started

Hardware: Colorlight 5A-75B Board

Get the tools: [OSS CAD Suite](https://github.com/yosyshq/oss-cad-suite-build)
- yosys
- nextpnr-ecp5
- openFPGALoader & openocd

### Preparing the board

Synthesize, route and flash to board:
```sh
make top && make route && make flash
```

For basic ARP not much additional work is needed. Run the following command:
```
# Test ARP (uses arping)
make arp
```

To test TCP, first, add route to hardcoded FPGA IP address. E.g. on Linux:
```sh
sudo ip route add 105.105.105.105 dev enp61s0 
```

The TCP echo server test will require re-compiling with the DEF_TCP_ECHO_EN parameter set.
```sh
DEF_TCP_ECHO_EN=1 make top && make route && make flash
# uses netcat
make tcp
```

Testing HTTP is a little more involved. 

A set of tools live in `tools/` which convert html pages inside the directory into the memory init files required.
```sh
# inside 'tools/'
python3 content_gen.py
```

Write the HTTP pages into flash memory. Here we write it starting from 0x40000. If you change this, do update the corresponding parameter in `top.sv`. 
```sh
openFPGALoader -c digilent_hs2 -f -o 0x40000 --verbose-level 2 --unprotect-flash tools/content.mem
# uses curl
make http
```

### Testing

cocotb test framework is used to automate tests found in `tb/`.

Install dependencies: `pip install -r requirements.txt`

Run tests within each directory e.g.: `python3 -m pytest test_tcp_integration.py`

## Design

![Block diagram](docs/FPGA-web-archi.svg)

### Assumptions

A set of simplifying assumptions to scope out the project.

HTTP
- HTTP1/2 protocol only.
- No TLS which means no HTTPS. This needs to be offered by a proxy.
- Headers entirely ignored.
- Only GET will be supported.

IP
- IPv4 only.
- Fragmentation unsupported.
- TCP only protocol support.

### Resources
- Board reverse engineering: https://github.com/q3k/chubby75
