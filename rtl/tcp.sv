package tcp;
  typedef enum logic [7:0] {
    CWR = 8'h80,
    ECE = 8'h40,
    URG = 8'h20,
    ACK = 8'h10,
    PSH = 8'h8,
    RST = 8'h4,
    SYN = 8'h2,
    FIN = 8'h1
  } tcp_flags_t;
  typedef enum logic [3:0] {
    LISTEN,
    SYN_RECV,
    ESTABLISHED,
    FINWAIT,
    FINWAIT2,
    CLOSEWAIT,
    CLOSING,
    LASTACK,
    TIMEWAIT,
    CLOSED
  } CONN_STATE;
  localparam MSS = 1460;
  // The number of packet payloads to keep in memory
  localparam BUFF_SIZE = 2;
  // payload and header must be aligned to 32 bits
  localparam BUFF_DATA_WIDTH = 32;
  // Number of bits to represent the memory address storing TCP payload
  localparam BUFF_WIDTH = $clog2(BUFF_SIZE);
  typedef struct packed {
    logic [31:0] peer_addr;
    logic [15:0] peer_port;
    // Address to payload in memory
    logic [18:0] payload_addr;
    logic [15:0] payload_size;
    // precomputed ones complement sum of payload and IP psuedo header
    logic [15:0] checksum;
    logic [7:0]  flags;
    // Ack number expected to receive for this packet. 
    // Filled up only at the time when the packet is sent as it may change.
    logic [31:0] ack_num;
    // sequence_num of received tcp packet
    logic [31:0] sequence_num;
    logic [15:0] window;
  } packet_t;
  typedef struct packed {
    // to identify this TCB uniquely
    logic [31:0] peer_addr;
    logic [15:0] peer_port;
    // Sequence number for transmitting our own data. It is the sequence_num
    // for the next transmit packet
    logic [31:0] sequence_num;
    // Ack number used for transmitting. i.e. the number expected by the
    // receiver (received sequence_num + 1)
    logic [31:0] ack_num;
    logic [15:0] window;

    CONN_STATE state;
  } tcb_t;

endpackage

