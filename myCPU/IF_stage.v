module IF_stage(
    input         clk,
    input         reset,
    //allwoin
    input         ds_allowin,
    //brbus
    input  [32:0] br_bus,
    //to ds
    output        fs_to_ds_valid,
    output [63:0] fs_to_ds_bus,
    // inst sram interface
    output        inst_sram_en,
    output [ 3:0] inst_sram_wen,
    output [31:0] inst_sram_addr,
    output [31:0] inst_sram_wdata,
    input  [31:0] inst_sram_rdata,
    // reflush
    input  [32:0] ws_reflush_fs_bus
);

reg         fs_valid;
wire        fs_ready_go;
wire        fs_allowin;
wire        to_fs_valid;

wire [31:0] seq_pc;
wire [31:0] nextpc;

// 考虑是否跳转
wire        br_taken;
wire [31:0] br_target;

// jump to sepc
wire ws_reflush_fs;
wire [31:0] ex_entry;
assign {ws_reflush_fs, ex_entry} = ws_reflush_fs_bus;

// 本阶段IF需要传给ID的信息
wire [31:0] fs_inst;
reg  [31:0] fs_pc;
wire        br_taken_cancel;

assign {br_taken, br_target} = br_bus;
assign fs_to_ds_bus = {fs_inst, fs_pc};
assign br_taken_cancel = ds_allowin && br_taken;

// pre-IF
assign to_fs_valid  = ~reset;
assign seq_pc       = fs_pc + 3'h4;
assign nextpc       = ws_reflush_fs ? ex_entry :
                     br_taken ? br_target : seq_pc; 

// IF
assign fs_ready_go    = 1'b1;
assign fs_allowin     = !fs_valid || fs_ready_go && ds_allowin;
assign fs_to_ds_valid =  fs_valid && fs_ready_go && !ws_reflush_fs;

always @(posedge clk) begin
    if (reset) begin
        fs_valid <= 1'b0;
    end
    else if (fs_allowin) begin
        fs_valid <= to_fs_valid;
    end
    else if(br_taken_cancel)
        fs_valid <= 1'b0;
end

always @(posedge clk) begin
    if (reset) begin
        fs_pc <= 32'h1bfffffc;
    end
    else if (fs_allowin) begin
        fs_pc <= nextpc;
    end
end

assign inst_sram_en    = to_fs_valid && fs_allowin;
assign inst_sram_wen   = 4'h0;
assign inst_sram_addr  = nextpc;
assign inst_sram_wdata = 32'b0;

assign fs_inst         = inst_sram_rdata;

endmodule