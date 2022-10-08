module MEM_stage(
    input         clk           ,
    input         reset         ,
    //allowin
    input         ws_allowin    ,
    output        ms_allowin    ,
    //from es
    input         es_to_ms_valid,
    input  [70:0] es_to_ms_bus  ,
    //to ws
    output        ms_to_ws_valid,
    output [69:0] ms_to_ws_bus  ,
    //from data-sram
    input  [31:0] data_sram_rdata,
    // to ds:: for data block
    output [ 4:0] ms_to_ds_dest,
    output [31:0] ms_to_ds_value
);

reg         ms_valid;
wire        ms_ready_go;

reg [70:0] es_to_ms_bus_r;
wire        ms_res_from_mem;
wire        ms_gr_we;
wire [ 4:0] ms_dest;
wire [31:0] ms_alu_result;
wire [31:0] ms_pc;
assign {ms_res_from_mem,  //70:70
        ms_gr_we       ,  //69:69
        ms_dest        ,  //68:64
        ms_alu_result  ,  //63:32
        ms_pc             //31:0
       } = es_to_ms_bus_r;

wire [31:0] mem_result;
wire [31:0] ms_final_result;

assign ms_to_ws_bus = {ms_gr_we       ,  //69:69
                       ms_dest        ,  //68:64
                       ms_final_result,  //63:32
                       ms_pc             //31:0
                      };

// this inst is to write reg(gr_we) and it's valid!!
assign ms_to_ds_dest = {5{ms_gr_we && ms_valid}} & ms_dest;
assign ms_to_ds_value = {32{ms_gr_we && ms_valid}} & ms_final_result;

assign ms_ready_go    = 1'b1;
assign ms_allowin     = !ms_valid || ms_ready_go && ws_allowin;
assign ms_to_ws_valid = ms_valid && ms_ready_go;
always @(posedge clk) begin
    if (reset) begin
        ms_valid <= 1'b0;
    end
    else if (ms_allowin) begin
        ms_valid <= es_to_ms_valid;
    end
end

always @(posedge clk) begin
    if (es_to_ms_valid && ms_allowin) begin
        es_to_ms_bus_r  <= es_to_ms_bus;
    end
end

assign mem_result = data_sram_rdata;

assign ms_final_result = ms_res_from_mem ? mem_result
                                         : ms_alu_result;

endmodule