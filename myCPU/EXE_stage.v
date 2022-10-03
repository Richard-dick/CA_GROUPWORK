module EXE_stage(
    input          clk,
    input          reset,
    //allowin
    input          ms_allowin,
    output         es_allowin,
    //from ds
    input          ds_to_es_valid,
    input  [154:0] ds_to_es_bus,
    //to ms
    output        es_to_ms_valid,
    output [70:0] es_to_ms_bus,
    // data sram interface
    output        data_sram_en,
    output [ 3:0] data_sram_wen,
    output [31:0] data_sram_addr,
    output [31:0] data_sram_wdata,
    // to ds:: for data block
    output [ 4:0] es_to_ds_dest,
    output [31:0] es_to_ds_value,
    output        es_value_from_mem
);

reg         es_valid;
wire        es_ready_go;

reg  [154:0] ds_to_es_bus_r;
wire [11:0] es_alu_op;
wire        es_res_from_mem;
wire        es_gr_we;
wire        es_mem_we;
wire [ 4:0] es_dest;
wire [31:0] es_pc;
wire [31:0] es_alu_src1;
wire [31:0] es_alu_src2;
wire [31:0] es_alu_result;
wire [31:0] es_final_result;
wire [31:0] rkd_value;
wire [ 7:0] es_mul_div_op;
wire        es_mul;
wire        es_div;
wire [63:0] unsigned_prod, signed_prod;
wire [31:0] es_mul_result;
wire [31:0] q_result;
wire [31:0] r_result;

 
wire        divisor_ready;
reg         div_valid;
wire        dividend_ready;
wire [63:0] div_result;
wire        div_done;

wire        udivisor_ready;
reg         udiv_valid;
wire        udividend_ready;
wire [63:0] udiv_result;
wire        udiv_done;

wire [31:0] es_div_result;

assign {
    es_mul_div_op,      //154:148
    es_pc,              //147:116
    // alu
    es_alu_op,          //115:104
    es_alu_src1,        //103:72
    es_alu_src2,        //71:40
    //mem
    rkd_value,
    es_res_from_mem,    //7:7
    es_mem_we,          //6:6
    //wb
    es_dest,            //5:1
    es_gr_we            //0:0
} = ds_to_es_bus_r;

assign unsigned_prod = es_alu_src1 * es_alu_src2;
assign signed_prod = $signed(es_alu_src1) * $signed(es_alu_src2);

assign es_mul = |es_mul_div_op[2:0];
assign es_div = |es_mul_div_op[6:3];
assign es_mul_result = {32{es_mul_div_op[0]}} & unsigned_prod[31:0]     //mul
                     | {32{es_mul_div_op[1]}} & signed_prod[63:32]       //mulh
                     | {32{es_mul_div_op[2]}} & unsigned_prod[63:32];   //mulh_u

assign es_to_ms_bus = {es_res_from_mem,  //70:70
                       es_gr_we       ,  //69:69
                       es_dest        ,  //68:64
                       es_final_result  ,  //63:32
                       es_pc             //31:0
                      };

assign es_final_result = es_mul ? es_mul_result :
                         es_div ? es_div_result : es_alu_result;


// this inst is to write reg(gr_we) and it's valid!!
assign es_to_ds_dest = {5{es_gr_we && es_valid}} & es_dest;
assign es_to_ds_value = {32{es_gr_we && es_valid}} & es_alu_result;
assign es_value_from_mem = es_valid && es_res_from_mem;

assign es_ready_go    = ~(|es_mul_div_op[6:3] && ~(udiv_done || div_done));//1'b1; // 是div指令，且没有done
assign es_allowin     = !es_valid || es_ready_go && ms_allowin;
assign es_to_ms_valid =  es_valid && es_ready_go;

always @(posedge clk) begin
    if (reset) begin
        es_valid <= 1'b0;
    end
    else if (es_allowin) begin
        es_valid <= ds_to_es_valid;
    end
end

always @(posedge clk) begin
    if (ds_to_es_valid && es_allowin) begin
        ds_to_es_bus_r <= ds_to_es_bus;
    end
end

always @(posedge clk)
begin
    if(reset) begin
        div_valid <= 1'b0;
    end
    else if(div_valid & divisor_ready & dividend_ready) begin
        div_valid <= 1'b0;
    end
    else if(ds_to_es_valid && es_allowin) begin
        div_valid <= | ds_to_es_bus[152:151];
    end
end

always @(posedge clk)
begin
    if(reset) begin
        udiv_valid <= 1'b0;
    end
    else if(udiv_valid & udivisor_ready & udividend_ready) begin
        udiv_valid <= 1'b0;
    end
    else if(ds_to_es_valid && es_allowin) begin
        udiv_valid <= | ds_to_es_bus[154:153];
    end
end

// always @(posedge clk) begin
//     if(reset) begin
//         es_div_result <= 32'b0;
//     end
//     else if(div_done) begin
//         es_div_result = {32{es_mul_div_op[3]}} & div_result[63:32]
//                             | {32{es_mul_div_op[4]}} & div_result[31:0];
//     end
//     else if (udiv_done) begin
//         es_div_result = {32{es_mul_div_op[5]}} & udiv_result[63:32]
//                             | {32{es_mul_div_op[6]}} & udiv_result[31:0];
//     end
// end

assign q_result = {32{es_mul_div_op[3]}} & div_result[63:32] | {32{es_mul_div_op[5]}} & udiv_result[63:32];
assign r_result = {32{es_mul_div_op[4]}} & div_result[31:0] | {32{es_mul_div_op[6]}} & udiv_result[31:0];

assign es_div_result = q_result | r_result;

alu u_alu(
    .alu_op     (es_alu_op    ),
    .alu_src1   (es_alu_src1  ),
    .alu_src2   (es_alu_src2  ),
    .alu_result (es_alu_result)
    );

signed_divider my_signed_divider(
    .aclk                   (clk),
    // S_AXIS_DIVISOR: rk
    .s_axis_divisor_tdata   (es_alu_src2),
    .s_axis_divisor_tready  (divisor_ready),
    .s_axis_divisor_tvalid  (div_valid),
    // S_AXIS_DIVIDEND: rj
    .s_axis_dividend_tdata  (es_alu_src1),
    .s_axis_dividend_tready (dividend_ready),
    .s_axis_dividend_tvalid (div_valid),
    // M_AXIS_DOUT
    .m_axis_dout_tdata      (div_result),
    .m_axis_dout_tvalid     (div_done)
);

unsigned_divider my_unsigned_divider(
    .aclk                   (clk),
    // S_AXIS_DIVISOR: rk
    .s_axis_divisor_tdata   (es_alu_src2),
    .s_axis_divisor_tready  (udivisor_ready),
    .s_axis_divisor_tvalid  (udiv_valid),
    // S_AXIS_DIVIDEND: rj
    .s_axis_dividend_tdata  (es_alu_src1),
    .s_axis_dividend_tready (udividend_ready),
    .s_axis_dividend_tvalid (udiv_valid),
    // M_AXIS_DOUT
    .m_axis_dout_tdata      (udiv_result),
    .m_axis_dout_tvalid     (udiv_done) 
);

assign data_sram_en    = 1'b1;
assign data_sram_wen   = es_mem_we && es_valid ? 4'hf : 4'h0;
assign data_sram_addr  = es_alu_result;
assign data_sram_wdata = rkd_value;

endmodule