module SRAM_AXI_bridge(
    input  wire        aclk,
    input  wire        aresetn,

    /* SRAM signals */
    // inst sram interface
    input  wire        inst_sram_req,   //en
    input  wire        inst_sram_wr,    //|wen
    input  wire [ 1:0] inst_sram_size, 
    input  wire [31:0] inst_sram_addr,
    input  wire [ 3:0] inst_sram_wstrb, //wen
    input  wire [31:0] inst_sram_wdata,
    output wire        inst_sram_addr_ok,
    output wire        inst_sram_data_ok,
    output wire [31:0] inst_sram_rdata,

    // data sram interface
    input  wire        data_sram_req,
    input  wire        data_sram_wr,
    input  wire [ 1:0] data_sram_size,
    input  wire [31:0] data_sram_addr,
    input  wire [ 3:0] data_sram_wstrb,
    input  wire [31:0] data_sram_wdata,
    output wire        data_sram_addr_ok,
    output wire        data_sram_data_ok,
    output wire [31:0] data_sram_rdata,

    /* AXI signals */
    // read request signals
    output wire [ 3:0] arid,
    output wire [31:0] araddr,
    output wire [ 7:0] arlen,
    output wire [ 2:0] arsize,
    output wire [ 1:0] arburst,
    output wire [ 1:0] arlock,
    output wire [ 3:0] arcache,
    output wire [ 2:0] arprot,
    output wire        arvalid,
    input  wire        arready,

    // read response signals
    input  wire [ 3:0] rid,
    input  wire [31:0] rdata,
    input  wire [ 1:0] rresp,
    input  wire        rlast,
    input  wire        rvalid,
    output wire        rready,

    // write request signals
    output wire [ 3:0] awid,
    output wire [31:0] awaddr,
    output wire [ 7:0] awlen,
    output wire [ 2:0] awsize,
    output wire [ 1:0] awburst,
    output wire [ 1:0] awlock,
    output wire [ 3:0] awcache,
    output wire [ 2:0] awprot,
    output wire        awvalid,
    input  wire        awready,

    // write data signals
    output wire [ 3:0] wid,
    output wire [31:0] wdata,
    output wire [ 3:0] wstrb,
    output wire        wlast,
    output wire        wvalid,
    input  wire        wready,

    // write response signals
    input  wire [ 3:0] bid,
    input  wire [ 1:0] bresp,
    input  wire        bvalid,
    output wire        bready
);

/* ???????????? */
    wire areset;
    assign areset = ~aresetn;
    
    // ???????????????
    reg [2:0] ar_current_state;
    reg [2:0] ar_next_state;
    reg [2:0] r_current_state;
    reg [2:0] r_next_state;
    reg [2:0] aw_current_state;
    reg [2:0] aw_next_state;
    reg [1:0] b_current_state;
    reg [1:0] b_next_state;

    // ????????????
    wire rd_inst_sram_req;  // ???????????????
    wire rd_data_sram_req;  // ???????????????
    wire wr_data_sram_req;  // ???????????????

    // ?????????
    reg  [3:0]  arid_r;
    reg  [31:0] araddr_r;
    reg  [1:0]  arsize_r;
    reg         arvalid_r;

    // ?????????
    reg rready_r;

    // ?????????
    reg [31:0]  awaddr_r;
    reg [2:0]   awsize_r;
    reg         awvalid_r;

    // ?????????
    reg [31:0] wdata_r;
    reg [3:0]  wstrb_r;
    reg        wvalid_r;

    // ?????????
    reg bready_r;

    // SRAM
    reg [31:0] inst_sram_rdata_r;
    reg [31:0] data_sram_rdata_r;

    assign rd_inst_sram_req = inst_sram_req && ~inst_sram_wr;      
    assign rd_data_sram_req = data_sram_req && ~data_sram_wr;
    assign wr_data_sram_req = data_sram_req &&  data_sram_wr;

/* ????????? */
    localparam  R_INIT   = 3'b001,
                R_DATA   = 3'b010,
                R_INST   = 3'b100,
                W_INIT   = 3'b001,
                W_ADDR   = 3'b010,
                W_DATA   = 3'b100,
                B_INIT   = 2'b01,
                B_DATA   = 2'b10;

    always @(posedge aclk) begin
        if(!aresetn) begin
            ar_current_state <= R_INIT;
            r_current_state  <= R_INIT;
            aw_current_state <= W_INIT;
            b_current_state  <= B_INIT;
        end
        else begin
            ar_current_state <= ar_next_state;
            r_current_state  <= r_next_state;
            aw_current_state <= aw_next_state;
            b_current_state  <= b_next_state;
        end
    end

    always @(*) begin
        case(ar_current_state)
            R_INIT: begin
                if(rd_data_sram_req)        // ???????????????????????????????????????
                    ar_next_state = R_DATA;
                else if(rd_inst_sram_req)   // ???????????????????????????????????????
                    ar_next_state = R_INST;
                else
                    ar_next_state = R_INIT;
            end
            R_INST: begin
                if(rvalid && rready)        // ???????????????????????????????????????????????????????????????
                    ar_next_state = R_INIT;
                else
                    ar_next_state = R_INST;
            end
            R_DATA: begin
                if(rvalid && rready)        // ???????????????????????????????????????????????????????????????
                    ar_next_state = R_INIT;
                else
                    ar_next_state = R_DATA;
            end
        endcase
    end

    always @(*) begin
        // ????????????ar?????????????????????????????????R_INIT???????????????????????????R_DATA????????????????????????
        // ???R_INIT???R_DATA????????????????????????????????????????????????????????????????????????
        case(r_current_state)       
            R_INIT: begin
                if(rd_data_sram_req)
                    r_next_state = R_DATA;
                else if(rd_inst_sram_req)
                    r_next_state = R_INST;
                else
                    r_next_state = R_INIT;
            end
            R_INST: begin
                if(rvalid && rready)
                    r_next_state = R_INIT;
                else
                    r_next_state = R_INST;
            end
            R_DATA: begin
                if(rvalid && rready)
                    r_next_state = R_INIT;
                else
                    r_next_state = R_DATA;
            end
        endcase
    end

    always @(*) begin
        case(aw_current_state)
            W_INIT: begin
                if(wr_data_sram_req)        // ?????????????????????????????????????????????????????????
                    aw_next_state = W_ADDR;
                else
                    aw_next_state = W_INIT;
            end
            W_ADDR: begin
                if(awvalid && awready)      // ????????????????????????????????????????????????????????????
                    aw_next_state = W_DATA;
                else
                    aw_next_state = W_ADDR;
            end
            W_DATA: begin
                if(bvalid && bready)        // ???????????????????????????????????????????????????????????????????????????
                    aw_next_state = W_INIT;
                else
                    aw_next_state = W_DATA;
            end
        endcase
    end

    always @(*) begin
        case(b_current_state)
            B_INIT: begin
                if(wvalid && wready)    // ??????????????????????????????????????????????????????????????????????????????
                    b_next_state = B_DATA;
                else
                    b_next_state = B_INIT;
            end
            B_DATA: begin
                if(bvalid && bready)    // ?????????????????????????????????????????????????????????????????????
                    b_next_state = B_INIT;
                else
                    b_next_state = B_DATA;
            end
        endcase
    end

/* read request signals */
    // R_INIT????????????????????????arid, araddr???arsize?????????????????????????????????
    always @(posedge aclk) begin
        if(!aresetn)
            arid_r <= 4'd0;
        else if(ar_current_state == R_INIT && rd_data_sram_req)
            arid_r <= 4'd1;     // ????????????1??????????????????
        else if(ar_current_state == R_INIT && rd_inst_sram_req)
            arid_r <= 4'd0;     // ????????????0
    end

    always @(posedge aclk) begin
        if(!aresetn)
            araddr_r <= 32'd0;
        else if(ar_current_state == R_INIT && rd_data_sram_req)
            araddr_r <= {data_sram_addr[31:2], 2'd0};
        else if(ar_current_state == R_INIT && rd_inst_sram_req)
            araddr_r <= inst_sram_addr;
    end

    always @(posedge aclk) begin
        if(!aresetn)
            arsize_r <= 2'd0;
        else if(ar_current_state == R_INIT && rd_data_sram_req)
            arsize_r <= data_sram_size;
        else if(ar_current_state == R_INIT && rd_inst_sram_req)
            arsize_r <= inst_sram_size;
    end

    always @(posedge aclk) begin
        if(!aresetn)
            arvalid_r <= 1'b0;
        else if(ar_current_state == R_INIT && (rd_inst_sram_req || rd_data_sram_req))
            arvalid_r <= 1'b1;
        else if(arready)
            arvalid_r <= 1'b0;
    end

    assign arid    = arid_r;
    assign araddr  = araddr_r;
    assign arlen   = 8'b0;
    assign arsize  = arsize_r;
    assign arburst = 2'b1;
    assign arlock  = 1'b0;
    assign arcache = 4'b0;
    assign arprot  = 3'b0;
    assign arvalid = arvalid_r;

/* read response signals */
    always @(posedge aclk) begin
        if(!aresetn)
            rready_r <= 1'b0;
        else if((r_current_state == R_DATA || r_current_state == R_INST) && rvalid && rready) // r_next_state == R_INIT
            rready_r <= 1'b0;
        else if((r_current_state == R_DATA || r_current_state == R_INST) && rvalid)
            rready_r <= 1'b1;
        // else if(rvalid)
        //     rready_r <= 1'b0;
    end

    assign rready = rready_r;

/* write request signals */
    always @(posedge aclk) begin
        if(!aresetn)
            awaddr_r <= 32'd0;
        else if(aw_current_state == W_INIT && wr_data_sram_req)
            awaddr_r <= data_sram_addr;
        else if(bvalid) // ?????????????????????????????????????????????
            awaddr_r <= 32'b0;
    end

    always @(posedge aclk) begin
        if(!aresetn)
            awsize_r <= 3'b0;
        else if(aw_current_state == W_INIT && wr_data_sram_req)
            awsize_r <= data_sram_size;
        else if(bvalid) // ???????????????????????????????????????
            awsize_r <= 3'b0;
    end

    always @(posedge aclk) begin
        if(!aresetn)
            awvalid_r <= 1'b0;
        else if(aw_current_state == W_INIT && wr_data_sram_req)
            awvalid_r <= 1'b1;
        else if(awready) // ?????????????????????
            awvalid_r <= 1'b0;
    end

    assign awid     = 4'b1;
    assign awaddr   = awaddr_r;
    assign awlen    = 8'b0;
    assign awsize   = awsize_r;
    assign awburst  = 2'b01;
    assign awlock   = 1'b0;
    assign awcache  = 4'b0;
    assign awprot   = 3'b0;
    assign awvalid  = awvalid_r;

/* write data signals */
    always @(posedge aclk) begin
        if(!aresetn)
            wdata_r<= 32'b0;
        else if(aw_current_state == W_INIT && wr_data_sram_req)
            wdata_r <= data_sram_wdata;
        else if(bvalid)
            wdata_r <= 32'b0;
    end

    always @(posedge aclk) begin
        if(!aresetn)
            wstrb_r <= 4'b0;
        else if(aw_current_state == W_INIT && wr_data_sram_req)
            wstrb_r <= data_sram_wstrb;
        else if(bvalid)
            wstrb_r <= 4'b0;
    end

    always @(posedge aclk) begin
        if(!aresetn)
            wvalid_r <= 1'b0;
        else if(aw_current_state == W_ADDR && awvalid && awready)
            wvalid_r <= 1'b1;
        else if(wready)
            wvalid_r <= 1'b0;
    end

    assign wid      = 4'b1;
    assign wdata    = wdata_r;
    assign wstrb    = wstrb_r;
    assign wlast    = 1'b1;
    assign wvalid   = wvalid_r;

/* write response signals */
    always @(posedge aclk) begin
        if(!aresetn)
            bready_r <= 1'b0;
        else if(b_current_state == B_INIT && wvalid && wready)
            bready_r <= 1'b1;
        else if(bvalid)
            bready_r <= 1'b0;
    end
    assign bready = bready_r;

/* SRAM */
    // ??????ok?????????ok
    assign inst_sram_addr_ok = ((ar_current_state == R_INIT) && rd_inst_sram_req && ~rd_data_sram_req);  
    assign data_sram_addr_ok = ((ar_current_state == R_INIT) && rd_data_sram_req ) ||  ((aw_current_state == W_INIT) && wr_data_sram_req);
    assign inst_sram_data_ok = ((r_current_state == R_INST) && rvalid && rready);
    assign data_sram_data_ok = ((r_current_state == R_DATA) && rvalid && rready) ||  ((aw_current_state == W_DATA) && bvalid);

    always @(posedge aclk) begin
        if(!aresetn)
            inst_sram_rdata_r <= 32'b0;
        else if(r_current_state == R_INST && (arid == 4'd0) && rvalid)
            inst_sram_rdata_r <= rdata;
    end

    always @(posedge aclk) begin
        if(!aresetn)
            data_sram_rdata_r <= 32'b0;
        else if(r_current_state == R_DATA && (arid == 4'd1) && rvalid)
            data_sram_rdata_r <= rdata;
    end

    assign inst_sram_rdata = inst_sram_rdata_r;
    assign data_sram_rdata = data_sram_rdata_r;

endmodule