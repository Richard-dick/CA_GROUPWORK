module cache(
    input  wire          clk,
    input  wire          resetn,

    // Cache-CPU interface
    input  wire          valid  ,
    input  wire          op     ,
    input  wire [7  :0]  index  ,
    input  wire [19 :0]  tag    ,
    input  wire [3  :0]  offset ,
    input  wire [3  :0]  wstrb  ,
    input  wire [31 :0]  wdata  ,
    
    output wire          addr_ok,
    output wire          data_ok,
    output wire [31 :0]  rdata  ,

    // Cache-AXI interface
    output wire          rd_req   ,
    output wire [2  :0]  rd_type  ,
    output wire [31 :0]  rd_addr  ,
    input  wire          rd_rdy   ,
    input  wire          ret_valid,
    input  wire          ret_last ,
    input  wire [31 :0]  ret_data ,

    output wire          wr_req  ,
    output wire [2  :0]  wr_type ,
    output wire [31 :0]  wr_addr ,
    output wire [3  :0]  wr_wstrb,
    output wire [127:0]  wr_data ,
    input  wire          wr_rdy  
);

//* State 
reg [5 :0] m_current_state;
reg [5 :0] m_next_state;
reg [5 :0] w_current_state;
reg [5 :0] w_next_state;

//* Cache line
wire         way0_tagv_we;
wire [7  :0] way0_tagv_addr;
wire [20 :0] way0_tagv_wdata;
wire [20 :0] way0_tagv_rdata;
wire [19 :0] way0_tag;
wire         way0_v;

reg  [255:0] way0_d;

wire [3  :0] way0_bank0_we;
wire [7  :0] way0_bank0_addr;
wire [31 :0] way0_bank0_wdata;
wire [31 :0] way0_bank0_rdata;
wire [3  :0] way0_bank1_we;
wire [7  :0] way0_bank1_addr;
wire [31 :0] way0_bank1_wdata;
wire [31 :0] way0_bank1_rdata;
wire [3  :0] way0_bank2_we;
wire [7  :0] way0_bank2_addr;
wire [31 :0] way0_bank2_wdata;
wire [31 :0] way0_bank2_rdata;
wire [3  :0] way0_bank3_we;
wire [7  :0] way0_bank3_addr;
wire [31 :0] way0_bank3_wdata;
wire [31 :0] way0_bank3_rdata;

wire         way1_tagv_we;
wire [7  :0] way1_tagv_addr;
wire [20 :0] way1_tagv_wdata;
wire [20 :0] way1_tagv_rdata;
wire [19 :0] way1_tag;
wire         way1_v;

reg  [255:0] way1_d;

wire [3  :0] way1_bank0_we;
wire [7  :0] way1_bank0_addr;
wire [31 :0] way1_bank0_wdata;
wire [31 :0] way1_bank0_rdata;
wire [3  :0] way1_bank1_we;
wire [7  :0] way1_bank1_addr;
wire [31 :0] way1_bank1_wdata;
wire [31 :0] way1_bank1_rdata;
wire [3  :0] way1_bank2_we;
wire [7  :0] way1_bank2_addr;
wire [31 :0] way1_bank2_wdata;
wire [31 :0] way1_bank2_rdata;
wire [3  :0] way1_bank3_we;
wire [7  :0] way1_bank3_addr;
wire [31 :0] way1_bank3_wdata;
wire [31 :0] way1_bank3_rdata;

//* Request Buffer
wire        request_happen;
wire [68:0] request_buffer;
reg  [68:0] request_buffer_r;
wire        op_r;
wire [7 :0] index_r;
wire [19:0] tag_r;
wire [3 :0] offset_r;
wire [3 :0] wstrb_r;
wire [31:0] wdata_r;

//* Tag Compare
wire way0_hit;
wire way1_hit;
wire cache_hit;

//* Data Select
// Which bank is the data from?
wire         sel_bank0;
wire         sel_bank1;
wire         sel_bank2;
wire         sel_bank3;
// The following variables are used for load hit
wire [31 :0] way0_load_word;
wire [31 :0] way1_load_word;
wire [31 :0] load_res;
// The following variable is used for replace
wire [127:0] replace_data;

//* Miss Buffer
wire       replace_way;
reg [1 :0] ret_data_num;
reg [31:0] miss_bank0;
reg [31:0] miss_bank1;
reg [31:0] miss_bank2;
reg [31:0] miss_bank3;

//* LFSR
reg [15:0] LFSR;

//* Write Buffer
wire        hit_write;
wire        hit_write_conflict;
wire [46:0] write_buffer;
reg  [46:0] write_buffer_r;
wire        hw_way;
wire [1 :0] hw_bank;
wire [31:0] hw_data;
wire [3 :0] hw_wstrb;
wire [7 :0] hw_index;

//* Refill Buffer
wire [31:0] refill_rdata;
wire [31:0] refill_bank_data;
wire [3 :0] refill_bank_wstrb;

/* Define state machine */
//* STATES
localparam IDLE    = 6'b000001,
           LOOKUP  = 6'b000010,
           MISS    = 6'b000100,
           REFILL  = 6'b001000,
           REPLACE = 6'b010000,
           WRITE   = 6'b100000;

//* NEXT STATE
// 主状态机
always @(posedge clk) begin
    if(!resetn) 
        m_current_state <= IDLE;
    else
        m_current_state <= m_next_state;
end

always @(*) begin
    case(m_current_state)
        IDLE: begin
            if(valid && !hit_write_conflict)
                m_next_state = LOOKUP;
            else
                m_next_state = IDLE;
        end

        LOOKUP: begin
            if(!cache_hit)
                m_next_state = MISS;
            else if(!hit_write_conflict)
                m_next_state = IDLE;
            else
                m_next_state = LOOKUP;
        end

        MISS: begin
            if(wr_rdy)
                m_next_state = REPLACE;
            else
                m_next_state = MISS;
        end

        REPLACE: begin
            if(rd_rdy)
                m_next_state = REFILL;
            else
                m_next_state = REPLACE;
        end

        REFILL: begin
            if(ret_last && ret_valid)
                m_next_state = IDLE;
            else
                m_next_state = REFILL;
        end

        default:
            m_next_state = IDLE;
    endcase
end

// Write Buffer状态机
always @(posedge clk) begin
    if(!resetn)
        w_current_state <= IDLE;
    else
        w_current_state <= w_next_state;
end

always @(*) begin
    case(w_current_state)
        IDLE: begin
            if(hit_write)
                w_next_state = WRITE;
            else
                w_next_state = IDLE;
        end

        WRITE: begin
            if(hit_write)
                w_next_state = WRITE;
            else
                w_next_state = IDLE;
        end
    endcase
end

/* Request Buffer */
// When load/store request happens, take down request info
assign request_happen = (m_current_state == IDLE) && valid;
assign request_buffer = {op,
                         index,
                         tag,
                         offset,
                         wstrb,
                         wdata};
always @(posedge clk) begin
    if(!resetn)
        request_buffer_r <= {69{1'b0}};
    else if(request_happen)
        request_buffer_r <= request_buffer;
end
assign {op_r,
        index_r,
        tag_r,
        offset_r,
        wstrb_r,
        wdata_r} = request_buffer_r;

/* AXI & Refill */
// addr_ok: a new request happens, and hit write, if exists, does not conflict with this request(no matter it is load or store)
assign addr_ok = request_happen && !(offset[3:2] == hw_bank && tag == tag_r && w_current_state == WRITE);
assign data_ok = (m_current_state == LOOKUP && cache_hit && op_r == 1'b0) // read hit
              || (w_current_state == WRITE) || (ret_valid && ret_last);   // write (hit, or AXI request)
// Actually load_res need not consider miss because that data would be returned from AXI in the form of refill_rdata
assign rdata = {32{m_current_state == REFILL && ret_valid && ret_last}} & refill_rdata |
               {32{m_current_state == LOOKUP && cache_hit}} & load_res; 
assign refill_rdata = {32{offset_r[3:2] == 2'b00}} & miss_bank0
                    | {32{offset_r[3:2] == 2'b01}} & miss_bank1
                    | {32{offset_r[3:2] == 2'b10}} & miss_bank2
                    | {32{offset_r[3:2] == 2'b11}} & miss_bank3;
assign refill_bank_data  = (ret_data_num == offset_r[3:2] && op_r == 1'b1) ? wdata_r : ret_data;
assign refill_bank_wstrb = (ret_data_num == offset_r[3:2] && op_r == 1'b1) ? wstrb_r : 4'b1111;

/* Read/Write Cache RAM */
// TAGV RAM
tagv_ram tagv_ram_0(
    .clka   (clk),
    // .ena    (!cache_hit),
    .wea    (way0_tagv_we),
    .addra  (way0_tagv_addr),
    .dina   (way0_tagv_wdata),
    .douta  (way0_tagv_rdata)
);
tagv_ram tagv_ram_1(
    .clka   (clk),
    // .ena    (!cache_hit),
    .wea    (way1_tagv_we),
    .addra  (way1_tagv_addr),
    .dina   (way1_tagv_wdata),
    .douta  (way1_tagv_rdata)
);
assign way0_tagv_addr = way0_tagv_we ? index_r : index;
assign way0_tagv_wdata = {tag_r, 1'b1};
assign way0_tagv_we = (m_current_state == REFILL && replace_way == 1'b0);
assign {way0_tag, way0_v} = way0_tagv_rdata;

assign way1_tagv_addr = way1_tagv_we ? index_r : index;
assign way1_tagv_wdata = {tag_r, 1'b1};
assign way1_tagv_we = (m_current_state == REFILL && replace_way == 1'b1);
assign {way1_tag, way1_v} = way1_tagv_rdata;

// DATA BANK RAM
data_bank_ram data_bank0_ram_0(
    .clka   (clk),
    // .ena    (!cache_hit),
    .wea    (way0_bank0_we),
    .addra  (way0_bank0_addr),
    .dina   (way0_bank0_wdata),
    .douta  (way0_bank0_rdata)
);
data_bank_ram data_bank1_ram_0(
    .clka   (clk),
    // .ena    (!cache_hit),
    .wea    (way0_bank1_we),
    .addra  (way0_bank1_addr),
    .dina   (way0_bank1_wdata),
    .douta  (way0_bank1_rdata)
);
data_bank_ram data_bank2_ram_0(
    .clka   (clk),
    // .ena    (!cache_hit),
    .wea    (way0_bank2_we),
    .addra  (way0_bank2_addr),
    .dina   (way0_bank2_wdata),
    .douta  (way0_bank2_rdata)
);
data_bank_ram data_bank3_ram_0(
    .clka   (clk),
    // .ena    (!cache_hit),
    .wea    (way0_bank3_we),
    .addra  (way0_bank3_addr),
    .dina   (way0_bank3_wdata),
    .douta  (way0_bank3_rdata)
);

data_bank_ram data_bank0_ram_1(
    .clka   (clk),
    // .ena    (!cache_hit),
    .wea    (way1_bank0_we),
    .addra  (way1_bank0_addr),
    .dina   (way1_bank0_wdata),
    .douta  (way1_bank0_rdata)
);
data_bank_ram data_bank1_ram_1(
    .clka   (clk),
    // .ena    (!cache_hit),
    .wea    (way1_bank1_we),
    .addra  (way1_bank1_addr),
    .dina   (way1_bank1_wdata),
    .douta  (way1_bank1_rdata)
);
data_bank_ram data_bank2_ram_1(
    .clka   (clk),
    // .ena    (!cache_hit),
    .wea    (way1_bank2_we),
    .addra  (way1_bank2_addr),
    .dina   (way1_bank2_wdata),
    .douta  (way1_bank2_rdata)
);
data_bank_ram data_bank3_ram_1(
    .clka   (clk),
    // .ena    (!cache_hit),
    .wea    (way1_bank3_we),
    .addra  (way1_bank3_addr),
    .dina   (way1_bank3_wdata),
    .douta  (way1_bank3_rdata)
);
// we condition: hit write OR refill
assign way0_bank0_we = {4{(w_current_state == WRITE && hw_bank == 2'b00 && hw_way == 1'b0) 
                       || (ret_valid && ret_data_num == 2'b00 && replace_way == 1'b0)}} 
                     & ((ret_valid && ret_data_num == 2'b00) ? refill_bank_wstrb : hw_wstrb);
assign way0_bank1_we = {4{(w_current_state == WRITE && hw_bank == 2'b01 && hw_way == 1'b0) 
                       || (ret_valid && ret_data_num == 2'b01 && replace_way == 1'b0)}} 
                     & ((ret_valid && ret_data_num == 2'b01) ? refill_bank_wstrb : hw_wstrb);
assign way0_bank2_we = {4{(w_current_state == WRITE && hw_bank == 2'b10 && hw_way == 1'b0) 
                       || (ret_valid && ret_data_num == 2'b10 && replace_way == 1'b0)}} 
                     & ((ret_valid && ret_data_num == 2'b10) ? refill_bank_wstrb : hw_wstrb);
assign way0_bank3_we = {4{(w_current_state == WRITE && hw_bank == 2'b11 && hw_way == 1'b0) 
                       || (ret_valid && ret_data_num == 2'b11 && replace_way == 1'b0)}} 
                     & ((ret_valid && ret_data_num == 2'b11) ? refill_bank_wstrb : hw_wstrb);
assign way0_bank0_addr = ret_valid ? index_r : index;
assign way0_bank1_addr = ret_valid ? index_r : index;
assign way0_bank2_addr = ret_valid ? index_r : index;
assign way0_bank3_addr = ret_valid ? index_r : index;
assign way0_bank0_wdata = (ret_valid && ret_data_num == 2'b00) ? refill_bank_data : hw_data;
assign way0_bank1_wdata = (ret_valid && ret_data_num == 2'b01) ? refill_bank_data : hw_data;
assign way0_bank2_wdata = (ret_valid && ret_data_num == 2'b10) ? refill_bank_data : hw_data;
assign way0_bank3_wdata = (ret_valid && ret_data_num == 2'b11) ? refill_bank_data : hw_data;

assign way1_bank0_we = {4{(w_current_state == WRITE && hw_bank == 2'b00 && hw_way == 1'b1) || (ret_valid && ret_data_num == 2'b00 && replace_way == 1'b1)}} 
                     & ((ret_valid && ret_data_num == 2'b00) ? refill_bank_wstrb : hw_wstrb);
assign way1_bank1_we = {4{(w_current_state == WRITE && hw_bank == 2'b01 && hw_way == 1'b1) || (ret_valid && ret_data_num == 2'b01 && replace_way == 1'b1)}} 
                     & ((ret_valid && ret_data_num == 2'b01) ? refill_bank_wstrb : hw_wstrb);
assign way1_bank2_we = {4{(w_current_state == WRITE && hw_bank == 2'b10 && hw_way == 1'b1) || (ret_valid && ret_data_num == 2'b10 && replace_way == 1'b1)}} 
                     & ((ret_valid && ret_data_num == 2'b10) ? refill_bank_wstrb : hw_wstrb);
assign way1_bank3_we = {4{(w_current_state == WRITE && hw_bank == 2'b11 && hw_way == 1'b1) || (ret_valid && ret_data_num == 2'b11 && replace_way == 1'b1)}} 
                     & ((ret_valid && ret_data_num == 2'b11) ? refill_bank_wstrb : hw_wstrb);
assign way1_bank0_addr = ret_valid ? index_r : index;
assign way1_bank1_addr = ret_valid ? index_r : index;
assign way1_bank2_addr = ret_valid ? index_r : index;
assign way1_bank3_addr = ret_valid ? index_r : index;
assign way1_bank0_wdata = (ret_valid && ret_data_num == 2'b00) ? refill_bank_data : hw_data;
assign way1_bank1_wdata = (ret_valid && ret_data_num == 2'b01) ? refill_bank_data : hw_data;
assign way1_bank2_wdata = (ret_valid && ret_data_num == 2'b10) ? refill_bank_data : hw_data;
assign way1_bank3_wdata = (ret_valid && ret_data_num == 2'b11) ? refill_bank_data : hw_data;

/* Dirty */
always @(posedge clk) begin
    if(!resetn)
        way0_d <= 256'b0;
    else if(w_current_state == WRITE && way0_hit)
        way0_d[index_r] <= 1'b1;    // hit write, so this line will be dirty
    else if(m_current_state == REFILL && !replace_way)
        way0_d[index_r] <= op_r;
end
always @(posedge clk) begin
    if(!resetn)
        way1_d <= 256'b0;
    else if(w_current_state == WRITE && way1_hit)
        way1_d[index_r] <= 1'b1;    // hit write, so this line will be dirty
    else if(m_current_state == REFILL && replace_way)
        way1_d[index_r] <= op_r;
end

/* Tag Compare */ 
assign way0_hit  = way0_v && (way0_tag == tag_r);
assign way1_hit  = way1_v && (way1_tag == tag_r);
assign cache_hit = way0_hit || way1_hit;

/* Data Select */
assign sel_bank0 = (offset_r[3:2] == 2'b00);
assign sel_bank1 = (offset_r[3:2] == 2'b01);
assign sel_bank2 = (offset_r[3:2] == 2'b10);
assign sel_bank3 = (offset_r[3:2] == 2'b11);
assign way0_load_word = ({4{sel_bank0}} & way0_bank0_rdata) |
                        ({4{sel_bank1}} & way0_bank1_rdata) |
                        ({4{sel_bank2}} & way0_bank2_rdata) |
                        ({4{sel_bank3}} & way0_bank3_rdata) ;
assign way1_load_word = ({4{sel_bank0}} & way1_bank0_rdata) |
                        ({4{sel_bank1}} & way1_bank1_rdata) |
                        ({4{sel_bank2}} & way1_bank2_rdata) |
                        ({4{sel_bank3}} & way1_bank3_rdata) ;
assign load_res = ({32{way0_hit}} & way0_load_word) |
                  ({32{way1_hit}} & way1_load_word) |
                  ({32{~cache_hit && ret_valid}} & ret_data);
assign replace_data = replace_way ? 
                     {way1_bank3_rdata, way1_bank2_rdata, way1_bank1_rdata, way1_bank0_rdata} :
                     {way0_bank3_rdata, way0_bank2_rdata, way0_bank1_rdata, way0_bank0_rdata} ;

/* LFSR */
// Example is from Wikipedia [Linear-feedback shift register - Fibonacci LFSRs]
always @(posedge clk) begin
    if(!resetn)
        LFSR <= 16'b1010_1100_1110_0001;
    else
        LFSR <= {LFSR[14:0], LFSR[10] ^ LFSR[12] ^ LFSR[13] ^ LFSR[15]};
end

/* Miss Buffer */
assign replace_way = LFSR[0];
always @(posedge clk) begin
    if(!resetn)
        ret_data_num <= 2'b00;
    else if(ret_valid && ret_last)
        ret_data_num <= 2'b00;
    else if(ret_valid)
        ret_data_num <= ret_data_num + 2'b01;
end
// 如果是写store操作，且要写的bank是该miss_bank，那么把传入的数据
// 写入Cache RAM，否则还是写从Cache中读出来的数据
always @(posedge clk) begin
    if (!resetn)
        miss_bank0 <= 32'b0;
    else if (ret_valid && ret_data_num==2'b00)
        miss_bank0 <= (op_r == 1'b1 && sel_bank0) ? wdata_r : ret_data;
end
always @(posedge clk) begin
    if (!resetn)
        miss_bank1 <= 32'b0;
    else if (ret_valid && ret_data_num==2'b01)
        miss_bank1 <= (op_r == 1'b1 && sel_bank1) ? wdata_r : ret_data;
end
always @(posedge clk) begin
    if (!resetn)
        miss_bank2 <= 32'b0;
    else if (ret_valid && ret_data_num==2'b10)
        miss_bank2 <= (op_r == 1'b1 && sel_bank2) ? wdata_r : ret_data;
end
always @(posedge clk) begin
    if (!resetn)
        miss_bank3 <= 32'b0;
    else if (ret_valid && ret_data_num==2'b11)
        miss_bank3 <= (op_r == 1'b1 && sel_bank3) ? wdata_r : ret_data;
end

/* Write Buffer */
assign hit_write_conflict = (m_current_state == LOOKUP && hit_write && op == 1'b0 && valid && tag == tag_r && offset == offset_r) ||
                            (w_current_state == WRITE  && op == 1'b0 && valid && tag == tag_r && offset[3:2] == offset_r[3:2]);
assign hit_write = (op_r == 1'b1) &&        // write
                   (m_current_state == LOOKUP) && cache_hit ; // hit
assign write_buffer = {
    way1_hit,       // way
    offset_r[3:2],  // bank
    wdata_r,        // data
    wstrb_r,        // wstrb
    index_r         // index
};
always @(posedge clk) begin
    if(!resetn)
        write_buffer_r <= 47'b0;
    else if(hit_write)
        write_buffer_r <= write_buffer;
end
assign {hw_way,
        hw_bank,
        hw_data,
        hw_wstrb,
        hw_index} = write_buffer_r;

/* AXI */
// Note that read and write happens simultaneously
// read
assign rd_req   = (m_current_state == REPLACE);
assign rd_type  = 3'b100;
assign rd_addr  = {tag_r, index_r, offset_r};

// write
assign wr_req   = (m_current_state == REPLACE) && 
                ((way0_d && way0_v && !replace_way) ||
                 (way1_d && way1_v &&  replace_way));
assign wr_type  = 3'b100;
assign wr_wstrb = 4'b1111;
assign wr_data  = replace_way ? 
                {way1_bank3_rdata, way1_bank2_rdata, way1_bank1_rdata, way1_bank0_rdata} :
                {way0_bank3_rdata, way0_bank2_rdata, way0_bank1_rdata, way0_bank0_rdata} ;
assign wr_addr  = {(replace_way ? way1_tag : way0_tag), index_r, offset_r};

endmodule
