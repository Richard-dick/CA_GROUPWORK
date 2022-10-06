module MEM_stage(
    input         clk           ,
    input         reset         ,
    //allowin
    input         ws_allowin    ,
    output        ms_allowin    ,
    //from es
    input         es_to_ms_valid,
    input  [75:0] es_to_ms_bus  ,
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
wire [ 4:0] ms_ld_op;
wire        ms_res_from_mem;
wire        ms_gr_we;
wire [ 4:0] ms_dest;
wire [31:0] ms_alu_result;
wire [31:0] ms_pc;
assign {ms_ld_op,         //75:71
        ms_res_from_mem,  //70:70
        ms_gr_we       ,  //69:69
        ms_dest        ,  //68:64
        ms_alu_result  ,  //63:32
        ms_pc             //31:0
       } = es_to_ms_bus_r;

wire [31:0] mem_result;
wire [ 7:0] ld_b_bu_sel;
wire [31:0] ld_b_res;
wire [31:0] ld_bu_res;
wire [15:0] ld_h_hu_sel;
wire [31:0] ld_h_res;
wire [31:0] ld_hu_res;
wire [ 1:0] ld_vaddr;
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

assign ld_vaddr = ms_alu_result[1:0];
assign ld_b_bu_sel = (ld_vaddr == 2'b00) ? data_sram_rdata[ 7: 0] :
                     (ld_vaddr == 2'b01) ? data_sram_rdata[15: 8] :
                     (ld_vaddr == 2'b10) ? data_sram_rdata[23:16] :
                                           data_sram_rdata[31:24] ;
assign ld_b_res  = {{24{ld_b_bu_sel[7]}}, ld_b_bu_sel};     // sign-extension(signed number)
assign ld_bu_res = {{24{1'b0}}, ld_b_bu_sel};               // zero-extension(unsigned number)
assign ld_h_hu_sel = (ld_vaddr == 2'b00) ? data_sram_rdata[15: 0] :
                                           data_sram_rdata[31:16] ;
assign ld_h_res  = {{16{ld_h_hu_sel[15]}}, ld_h_hu_sel};    // sign-extension(signed number)
assign ld_hu_res = {{16{1'b0}}, ld_h_hu_sel};               // zero-extension(unsigned number)
assign mem_result = (ms_ld_op[0]) ? ld_b_res  :
                    (ms_ld_op[1]) ? ld_bu_res :
                    (ms_ld_op[2]) ? ld_h_res  :
                    (ms_ld_op[3]) ? ld_hu_res :
                                    data_sram_rdata;

assign ms_final_result = ms_res_from_mem ? mem_result
                                         : ms_alu_result;

endmodule