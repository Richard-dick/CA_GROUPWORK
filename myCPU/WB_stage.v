// CSR_NUM declaration
    `define CSR_CRMD      32'h0
    `define CSR_PRMD      32'h1
    `define CSR_ECFG      32'h4
    `define CSR_ESTAT     32'h5
    `define CSR_ERA       32'h6
    `define CSR_BADV      32'h7
    `define CSR_EENTRY    32'hc
    `define CSR_SAVE0     32'h30
    `define CSR_SAVE1     32'h31   
    `define CSR_SAVE2     32'h32
    `define CSR_SAVE3     32'h33
    `define CSR_TID       32'h40
    `define CSR_TCFG      32'h41
    `define CSR_TVAL      32'h42
    `define CSR_TICLR     32'h44
// EX_CODE declaration
    `define ECODE_INT     6'h0
    `define ECODE_PIL     6'h1
    `define ECODE_PIS     6'h2
    `define ECODE_PIF     6'h3
    `define ECODE_PME     6'h4
    `define ECODE_PPI     6'h7    
    `define ECODE_ADE     6'h8
    `define ECODE_ALE     6'h9
    `define ECODE_SYS     6'hb
    `define ECODE_BRK     6'hc
    `define ECODE_INE     6'hd
    `define ECODE_IPE     6'he
    `define ECODE_FPD     6'hf
    `define ECODE_TLBR    6'h3f 
    `define ESUBCODE_ADEF 9'h0  
    `define ESUBCODE_ADEM 9'h1

/*
 * WB阶段，是整个流水线的最后阶段
 * @ author: lzh //? coder: unknown
 * 负责功能：
 * 1. 通过ws_to_rf_bus，写回寄存器
 * 2. 直接和CSR模块交互
 * 3. 输出debug信号
 */


module WB_stage(
    input          clk,
    input          reset,

//* 和MEM阶段的流水线握手
    input          ms_to_ws_valid,
    input  [168:0] ms_to_ws_bus,
    output         ws_allowin,

//* 写回寄存器的 写使能 | 写地址 | 写数据
    output [37:0]  ws_to_rf_bus,

//* 数据相关的前递信号
    output        ws_csr, // ! 这个信号是和csr数据相关，直接阻塞掉
    output [ 4:0] ws_to_ds_dest,
    output [31:0] ws_to_ds_value,

//* 送往前面诸阶段的清空流水线信号
    output [32:0] ws_reflush_fs_bus,
    output        ws_reflush_ds,
    output        ws_reflush_es,
    output        ws_reflush_ms,

//* 中断信号，详见CSR.v：353
    output        has_int,

// trace debug interface 
    output [31:0] debug_wb_pc,
    output [ 3:0] debug_wb_rf_wen,
    output [ 4:0] debug_wb_rf_wnum,
    output [31:0] debug_wb_rf_wdata
);


/*
 * 信号声明区
 * @ author: lzh //? coder: unknown
 */
// csr交互
    wire ws_csr_we;
    wire ws_csr_rd;
    wire [31:0] ws_csr_wmask;
    wire [13:0] ws_csr_num;
    wire [31:0] csr_rvalue;

// 例外处理
    wire [16:0] ws_ex_cause_bus;
    wire [31:0] ws_vaddr;
    wire ws_ertn;
    wire ws_ex;
    wire ws_rdcntid;
    wire [5:0] ws_ecode;
    wire [8:0] ws_esubcode;
    wire [31:0] ex_entry;
    wire [31:0] era_entry;

// 没dio用
    wire ipi_int_in;
    wire [31:0] coreid_in;
    wire [7:0] hw_int_in;
    
// 流水线处理（数据传递+握手）
    reg         ws_valid;
    wire        ws_ready_go;
    reg [168:0] ms_to_ws_bus_r;
    wire        ws_gr_we;
    wire [ 4:0] ws_dest;
    wire [31:0] ws_final_result;
    wire [31:0] ws_pc;

// 寄存器
    wire        rf_we;
    wire [4 :0] rf_waddr;
    wire [31:0] rf_wdata;

/*
 * 功能区
 * @ author: lzh //? coder: unknown
 */

assign {//* 读取上一流水线信息
    ws_rdcntid,         //168:168
    ws_vaddr,           //167:136
    ws_ertn,            //135:135
    ws_csr_we,          //134:134
    ws_csr_rd,          //133:133
    ws_csr_wmask,       //132:101
    ws_csr_num,         //100:87
    ws_ex_cause_bus,    //86:70
    ws_gr_we,           //69:69
    ws_dest,            //68:64
    ws_final_result,    //63:32
    ws_pc               //31:0
    } = ms_to_ws_bus_r;

//* 例外处理区
    //? 在当前阶段valid的情况下，如果casuse_bus或者存在ertn信号则拉高
    assign ws_reflush_ds = ws_valid & 
                        (ws_ertn | (|ws_ex_cause_bus));
    assign ws_reflush_es = ws_reflush_ds;
    assign ws_reflush_ms = ws_reflush_ds;
    assign ws_reflush_fs_bus = {ws_valid & // valid stage
                            (ws_ertn | (|ws_ex_cause_bus)), // 有ertn或者有中断，则需flush
                            ws_ertn ? era_entry // ertn 恢复
                            :((|ws_ex_cause_bus)?(ex_entry):ws_pc+4)};  
    //? 触发中断
    assign ws_ex = ws_valid & (|ws_ex_cause_bus);
    //TODO: 只能记录最早报出的中断---需要修改
    assign ws_ecode = (ws_ex_cause_bus[6'h1] & ws_valid) ? `ECODE_SYS         
                    : (ws_ex_cause_bus[6'h2] & ws_valid) ? `ECODE_ADE
                    : (ws_ex_cause_bus[6'h3] & ws_valid) ? `ECODE_ALE
                    : (ws_ex_cause_bus[6'h4] & ws_valid) ? `ECODE_BRK
                    : (ws_ex_cause_bus[6'h5] & ws_valid) ? `ECODE_INE
                    : 6'b0;
    assign ws_esubcode = (ws_ex_cause_bus[6'h2] & ws_valid) ? `ESUBCODE_ADEF
                    : 9'b0;
    //? 没什么dio用的信号
    assign coreid_in  = 32'b0;
    assign hw_int_in  = 8'b0;
    assign ipi_int_in = 1'b0; 


//* 数据前递处理
    assign ws_csr = (ws_csr_we || ws_csr_rd) & ws_valid;
    assign ws_to_ds_dest = {5{ws_gr_we && ws_valid}} & ws_dest;
    assign ws_to_ds_value = {32{ws_gr_we && ws_valid}} & rf_wdata;

//* 流水线握手区
    assign ws_ready_go = 1'b1;
    assign ws_allowin  = !ws_valid || ws_ready_go;

    always @(posedge clk) begin
        if (reset) 
            ws_valid <= 1'b0;
        else if(ws_reflush_ds) 
            ws_valid <= 1'b0;
        else if (ws_allowin) 
            ws_valid <= ms_to_ws_valid;
    end

    always @(posedge clk) begin
        if (ms_to_ws_valid && ws_allowin) 
            ms_to_ws_bus_r <= ms_to_ws_bus;
    end

//* WB阶段对寄存器操作信号
    assign rf_we    = ws_gr_we && ws_valid;
    assign rf_waddr = ws_dest;
    assign rf_wdata = ws_csr_rd ? csr_rvalue : ws_rdcntid ? csr_rvalue : ws_final_result;
    assign ws_to_rf_bus = {rf_we   ,  //37:37
                        rf_waddr,  //36:32
                        rf_wdata   //31:0
                        };

// debug 信号连接
    assign debug_wb_pc       = ws_pc;
    assign debug_wb_rf_wen   = {4{rf_we}};
    assign debug_wb_rf_wnum  = ws_dest;
    assign debug_wb_rf_wdata = rf_wdata;

//* 模块实例化
csr inst_csr(
     .clk           (clk)
    ,.reset         (reset)
    ,.csr_num       (ws_csr_num)
    ,.csr_rvalue    (csr_rvalue)

    ,.csr_we        (ws_csr_we)
    ,.csr_wmask     (ws_csr_wmask)
    ,.csr_wvalue    (ws_final_result)
    
    ,.ws_ex         (ws_ex)
    ,.ws_pc         (ws_pc)
    ,.ws_ecode      (ws_ecode)
    ,.ws_esubcode   (ws_esubcode)
    ,.ws_vaddr      (ws_vaddr)
    ,.coreid_in     (coreid_in) 
    ,.ertn          (ws_ertn)

    ,.has_int       (has_int)
    ,.ex_entry      (ex_entry)
    ,.era_entry     (era_entry)
    ,.hw_int_in     (hw_int_in)
    ,.ipi_int_in    (ipi_int_in)
);

endmodule