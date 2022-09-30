module EXE_stage(
    input          clk,
    input          reset,
    //allowin
    input          ms_allowin,
    output         es_allowin,
    //from ds
    input          ds_to_es_valid,
    input  [147:0] ds_to_es_bus,
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

reg  [147:0] ds_to_es_bus_r;
wire [11:0] es_alu_op;
wire        es_res_from_mem;
wire        es_gr_we;
wire        es_mem_we;
wire [ 4:0] es_dest;
wire [31:0] es_pc;
wire [31:0] es_alu_src1;
wire [31:0] es_alu_src2;
wire [31:0] es_alu_result;
wire [31:0] rkd_value;

assign {
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

assign es_to_ms_bus = {es_res_from_mem,  //70:70
                       es_gr_we       ,  //69:69
                       es_dest        ,  //68:64
                       es_alu_result  ,  //63:32
                       es_pc             //31:0
                      };

// this inst is to write reg(gr_we) and it's valid!!
assign es_to_ds_dest = {5{es_gr_we && es_valid}} & es_dest;
assign es_to_ds_value = {32{es_gr_we && es_valid}} & es_alu_result;
assign es_value_from_mem = es_valid && es_res_from_mem;


assign es_ready_go    = 1'b1;
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


alu u_alu(
    .alu_op     (es_alu_op    ),
    .alu_src1   (es_alu_src1  ),
    .alu_src2   (es_alu_src2  ),
    .alu_result (es_alu_result)
    );

assign data_sram_en    = 1'b1;
assign data_sram_wen   = es_mem_we && es_valid ? 4'hf : 4'h0;
assign data_sram_addr  = es_alu_result;
assign data_sram_wdata = rkd_value;

endmodule