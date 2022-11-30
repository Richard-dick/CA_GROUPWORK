module IF_stage
#(
    parameter TLBNUM = 16
)
(
    input         clk,
    input         reset,
    //allwoin
    input         ds_allowin,
    //brbus
    input  [33:0] br_bus,
    //to ds
    output        fs_to_ds_valid,
    output [69:0] fs_to_ds_bus,
    // inst sram interface
    output        inst_sram_req,
    output        inst_sram_wr,
    output [ 1:0] inst_sram_size,
    output [31:0] inst_sram_addr,
    output [ 3:0] inst_sram_wstrb,
    output [31:0] inst_sram_wdata,
    input         inst_sram_addr_ok,
    input         inst_sram_data_ok,
    input [31:0]  inst_sram_rdata,
    // reflush
    input [32:0] ws_reflush_fs_bus,
        // 从ws阶段传来的4*32的value线
    input [127:0] ws_to_fs_bus,

    output [              18:0] s0_vppn,
    output                      s0_va_bit12,
    output [               9:0] s0_asid,
    input                       s0_found,
    input  [$clog2(TLBNUM)-1:0] s0_index,
    input  [              19:0] s0_ppn,
    input  [               5:0] s0_ps,
    input  [               1:0] s0_plv,
    input  [               1:0] s0_mat,
    input                       s0_d,
    input                       s0_v
);

reg         fs_valid;
wire        fs_ready_go;
wire        fs_allowin;

//pre-if
wire        to_fs_valid;
wire        to_fs_ready_go; 
reg         fs_inst_buffer_valid;
reg  [31:0] fs_inst_buffer;
reg         inst_sram_addr_ok_r;  //在fs_allowin之前，需要保持inst_sram_addr_ok

//缓存信息
reg        br_taken_r;
reg [31:0] br_target_r;
reg        ws_reflush_pfs_r;
reg [31:0] ex_entry_r;

wire [31:0] seq_pc;
wire [31:0] nextpc;

// 考虑是否跳转
wire        br_taken;
wire [31:0] br_target;
wire        br_stall;



// jump to sepc
wire ws_reflush_fs;
wire [31:0] ex_entry;
assign {ws_reflush_fs, ex_entry} = ws_reflush_fs_bus;

// 本阶段IF需要传给ID的信息
wire [31:0] fs_inst;
reg  [31:0] fs_pc;
wire        br_taken_cancel;

reg [1:0] fs_inst_cancel;
wire [ 5:0] tlb_ex_bus;
wire is_ex_adef;
assign {br_stall, br_taken, br_target} = br_bus;
assign fs_to_ds_bus = { tlb_ex_bus,
                        fs_inst, 
                        fs_pc, 
                        is_ex_adef};     // 将ADEF异常判断信号传到ID阶段，
                                        // 再由ex_cause_bus统一搭载传递至WB阶段
assign br_taken_cancel = ds_allowin && br_taken;

// pre-IF
assign to_fs_ready_go = (inst_sram_req && inst_sram_addr_ok) || inst_sram_addr_ok_r;
assign to_fs_valid    = to_fs_ready_go;
assign seq_pc         = fs_pc + 3'h4;
assign nextpc         = ws_reflush_pfs_r       ? ex_entry_r 
                      : ws_reflush_fs          ? ex_entry 
                      : br_taken_r             ? br_target_r
                      :(br_taken && !br_stall) ? br_target
                      : seq_pc;


always @(posedge clk) begin
    if(reset) 
        inst_sram_addr_ok_r <= 1'b0;
    else if(inst_sram_addr_ok && inst_sram_req && !fs_allowin)
        inst_sram_addr_ok_r <= 1'b1;
    else if(fs_allowin) 
        inst_sram_addr_ok_r <= 1'b0;
end


always @(posedge clk) begin
    if(reset) begin
        br_taken_r  <= 1'b0;
        br_target_r <= 32'b0;
    end
    else if(to_fs_ready_go && fs_allowin) begin
        br_taken_r  <= 1'b0;
        br_target_r <= 32'b0;
    end
    else if(br_taken && !br_stall) begin
        br_taken_r  <= 1'b1;
        br_target_r <= br_target;
    end
end

always @(posedge clk) begin
    if(reset) begin
        ws_reflush_pfs_r <= 1'b0;
        ex_entry_r <= 32'b0;
    end
    else if(to_fs_ready_go && fs_allowin) begin
        ws_reflush_pfs_r <= 1'b0;
        ex_entry_r <= 32'b0;
    end
    else if(ws_reflush_fs) begin
        ws_reflush_pfs_r <= 1'b1;
        ex_entry_r <= ex_entry;
    end
end

//对应讲义P193中间部分 指令在IF缓存
always @(posedge clk) begin
    if(reset) 
        fs_inst_buffer_valid <= 1'b0;
    else if (ds_allowin || ws_reflush_fs) 
        fs_inst_buffer_valid <= 1'b0;
    else if(!fs_inst_buffer_valid && inst_sram_data_ok && !(|fs_inst_cancel) && !ds_allowin)  //优先级 错误
        fs_inst_buffer_valid <= 1'b1;
    
    if(reset) 
        fs_inst_buffer <= 32'b0;
    else if(!fs_inst_buffer_valid && inst_sram_data_ok && !(|fs_inst_cancel) && !ds_allowin)
        fs_inst_buffer <= inst_sram_rdata;
end

// IF
assign fs_ready_go    = (fs_valid && inst_sram_data_ok || fs_inst_buffer_valid) && ~(|fs_inst_cancel);
assign fs_allowin     = !fs_valid || fs_ready_go && ds_allowin;
assign fs_to_ds_valid = fs_valid && fs_ready_go && !ws_reflush_fs && (~br_taken || br_stall);

always @(posedge clk) begin
    if (reset) begin
        fs_valid <= 1'b0;
    end
    else if (fs_allowin) begin
        fs_valid <= to_fs_valid;
    end
    else if(br_taken_cancel || ws_reflush_fs)  
        fs_valid <= 1'b0;
end

always @(posedge clk) begin
    if (reset) begin
        fs_pc <= 32'h1bfffffc;
    end
    else if (to_fs_ready_go && fs_allowin) begin
        fs_pc <= nextpc;
    end
end

//fs_inst_cancel 对应P194方法二
always @(posedge clk) begin
    if(reset) 
        fs_inst_cancel <= 2'b00;
    else if(!fs_allowin && !fs_ready_go && (br_taken && !br_stall))   //优先级 错误
        fs_inst_cancel <= fs_inst_cancel + 1;
    else if(!fs_allowin && !fs_ready_go && (ws_reflush_fs))   //优先级 错误
        fs_inst_cancel <= fs_inst_cancel + 1;
    else if(inst_sram_data_ok && fs_inst_cancel == 2'b10)
        fs_inst_cancel <= 2'b01;
    else if(inst_sram_data_ok && fs_inst_cancel == 2'b01)
        fs_inst_cancel <= 2'b00;
end

assign inst_sram_req   = ~reset && fs_allowin;
assign inst_sram_wr    = 1'h0;
assign inst_sram_size  = 2'h2;
// assign inst_sram_addr  = nextpc;
assign inst_sram_wstrb = 4'h0;
assign inst_sram_wdata = 32'h0;

assign fs_inst = fs_inst_buffer_valid ? fs_inst_buffer : inst_sram_rdata;


wire [31:0] csr_asid_rvalue;
wire [31:0] csr_crmd_rvalue;
wire [31:0] csr_dmw0_rvalue;
wire [31:0] csr_dmw1_rvalue;
assign {csr_crmd_rvalue, csr_dmw0_rvalue, csr_dmw1_rvalue, csr_asid_rvalue} = ws_to_fs_bus;

vaddr_transfer inst_transfer(
    .va        (nextpc),
    .inst_op   (3'b001),// 三类输入{load.store,inst}
    .pa        (inst_sram_addr),
    .tlb_ex_bus(tlb_ex_bus),//{PME,PPI,PIS,PIL,PIF,TLBR}
    // tlb:: 和s0连接
    .s_vppn    (s0_vppn),
    .s_va_bit12(s0_va_bit12),
    .s_asid    (s0_asid),
    .s_found   (s0_found),
    .s_index   (s0_index),
    .s_ppn     (s0_ppn),
    .s_ps      (s0_ps),
    .s_plv     (s0_plv),
    .s_mat     (s0_mat),
    .s_d       (s0_d),
    .s_v       (s0_v),
    // crmd:: 读入csr中信息做判断
    .csr_asid  (csr_asid_rvalue),
    .csr_crmd  (csr_crmd_rvalue),
    // crmd:: 读入csr中信息做判断
    .dmw_hit   (dmw_hit),
    .csr_dmw0  (csr_dmw0_rvalue),
    .csr_dmw1  (csr_dmw1_rvalue)
);

// whether ADEF exception occurs
// ADEF exception should happen at pre-IF stage


assign is_ex_adef = (nextpc[1:0] != 2'b00) || (nextpc[31] & (csr_crmd_rvalue[1:0]!=0)) & ~dmw_hit;
endmodule