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
  } TCP_FLAGS;
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
  localparam BUFF_SIZE = 4;
  // payload and header must be aligned to 32 bits
  localparam BUFF_DATA_WIDTH = 32;
  // Number of bits to represent the memory address storing TCP payload
  localparam BUFF_WIDTH = $clog2(BUFF_SIZE);
  typedef struct packed {
    logic [31:0] peer_addr;
    logic [15:0] peer_port;
    // Address to payload in memory
    logic [BUFF_WIDTH-1:0] payload_addr;
    logic [15:0] payload_size;
    // precomputed ones complement sum of payload and IP psuedo header
    logic [15:0] checksum;
    logic [7:0] flags;
    logic [15:0] window;
    // Ack number expected to receive for this packet. 
    // Filled up only at the time when the packet is sent as it may change.
    logic [31:0] ack_num;
    // sequence_num of received tcp packet
    logic [31:0] sequence_num;
  } packet_t;
  typedef struct packed {
    // to identify this TCB uniquely
    logic [31:0] peer_addr;
    logic [15:0] peer_port;
    // Sequence number for transmitting our own data.
    logic [31:0] sequence_num;
    // Ack number used for transmitting. i.e. the number expected by the
    // receiver (received sequence_num + 1)
    logic [31:0] ack_num;
    logic [15:0] window;

    // lists that identifies packets to be sent
    packet_t [BUFF_SIZE-1:0] to_be_sent;
    logic [BUFF_WIDTH:0] to_be_sent_wr_ptr;
    logic [BUFF_WIDTH:0] to_be_sent_rd_ptr;

    // list of packets already sent and waiting to be acked by peer
    packet_t [BUFF_SIZE-1:0] to_be_ack;
    logic [BUFF_WIDTH:0] to_be_ack_wr_ptr;
    logic [BUFF_WIDTH:0] to_be_ack_rd_ptr;
    CONN_STATE state;
  } tcb_t;

endpackage

