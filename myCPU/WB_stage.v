// CSR_NUM declaration
    `define CSR_CRMD      32'h0
    `define CSR_PRMD      32'h1
    `define CSR_ECFG      32'h4
    `define CSR_ESTAT     32'h5
    `define CSR_ERA       32'h6
    `define CSR_BADV      32'h7
    `define CSR_EENTRY    32'hc
    `define CSR_TLBIDX    32'h10
    `define CSR_TLBEHI    32'h11
    `define CSR_TLBELO0   32'h12
    `define CSR_TLBELO1   32'h13
    `define CSR_ASID      32'h18
    `define CSR_SAVE0     32'h30
    `define CSR_SAVE1     32'h31   
    `define CSR_SAVE2     32'h32
    `define CSR_SAVE3     32'h33
    `define CSR_TID       32'h40
    `define CSR_TCFG      32'h41
    `define CSR_TVAL      32'h42
    `define CSR_TICLR     32'h44
    `define CSR_TLBRENTRY 32'h88
    `define CSR_DMW0      32'h180
    `define CSR_DMW1      32'h181
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

module WB_stage
#(
    parameter TLBNUM = 16
)
(
    input          clk,
    input          reset,
    //allowin
    output         ws_allowin,
    //from ms
    input          ms_to_ws_valid,
    input  [173:0] ms_to_ws_bus,
    //to rf: for write back
    output [37:0]  ws_to_rf_bus,
    //trace debug interface
    output [31:0] debug_wb_pc,
    output [ 3:0] debug_wb_rf_wen,
    output [ 4:0] debug_wb_rf_wnum,
    output [31:0] debug_wb_rf_wdata,
    // to ds:: for data block
    output [ 4:0] ws_to_ds_dest,
    output [31:0] ws_to_ds_value,
    // to former stage:: exceptino flush
    output [32:0] ws_reflush_fs_bus,
    output        ws_reflush_ds,
    output        ws_reflush_es,
    output        ws_reflush_ms,

    output        has_int,
    // block
    output        ws_csr,

    // tlb:: wr, fill rd
    // write port
    output                      we,
    output [$clog2(TLBNUM)-1:0] w_index,
    output                      w_e,
    output [               5:0] w_ps,
    output [              18:0] w_vppn,
    output [               9:0] w_asid,
    output                      w_g,
    output [              19:0] w_ppn0,
    output [               1:0] w_plv0,
    output [               1:0] w_mat0,
    output                      w_d0,
    output                      w_v0,
    output [              19:0] w_ppn1,
    output [               1:0] w_plv1,
    output [               1:0] w_mat1,
    output                      w_d1,
    output                      w_v1,
    // read port
    output [$clog2(TLBNUM)-1:0] r_index,
    input                       r_e,
    input  [              18:0] r_vppn,
    input  [               5:0] r_ps,
    input  [               9:0] r_asid,
    input                       r_g,
    input  [              19:0] r_ppn0,
    input  [               1:0] r_plv0,
    input  [               1:0] r_mat0,
    input                       r_d0,
    input                       r_v0,
    input  [              19:0] r_ppn1,     
    input  [               1:0] r_plv1,
    input  [               1:0] r_mat1,
    input                       r_d1,
    input                       r_v1,
    // 从exe级传来的srch指令
    // output [63:0] to_es_tlb_bus, 
    input [38:0] to_ws_csr_bus,
    output [127:0] ws_to_fs_bus,
    output [159:0] ws_to_es_bus
);

reg         ws_valid;
wire        ws_ready_go;

reg [173:0] ms_to_ws_bus_r;
wire        ws_gr_we;
wire [ 4:0] ws_dest;
wire [31:0] ws_final_result;
wire [31:0] ws_pc;
wire [31:0] coreid_in;

// exp12 - kernel
wire ws_csr_we;
wire ws_csr_rd;
wire [31:0] ws_csr_wmask;
wire [13:0] ws_csr_num;
wire [16:0] ws_ex_cause_bus;
// port_csr_connection
wire [31:0] csr_rvalue;
wire [7:0] hw_int_in;
wire ipi_int_in;
// wire [31:0] csr_wvalue;
wire [31:0] ws_vaddr;
wire ws_ertn;
wire ws_ex;
wire ws_rdcntid;
wire [5:0] ws_ecode;
wire [8:0] ws_esubcode;
wire [31:0] ex_entry;
wire [31:0] era_entry;

wire [ 4:0] tlb_bus;
wire [ 4:0] ws_tlb_bus;

assign {
    ws_tlb_bus,         //173:169
    ws_rdcntid,         //168:168
    ws_vaddr,           //167:136
    ws_ertn,            //135:135
    ws_csr_we,          //134:134
    ws_csr_rd,          //133:133
    ws_csr_wmask,       //132:101
    ws_csr_num,         //100:87
    ws_ex_cause_bus,    //86:70
    ws_gr_we       ,  //69:69
    ws_dest        ,  //68:64
    ws_final_result,  //63:32
    ws_pc             //31:0
    } = ms_to_ws_bus_r;

wire        rf_we;
wire [4 :0] rf_waddr;
wire [31:0] rf_wdata;
assign ws_to_rf_bus = {rf_we   ,  //37:37
                       rf_waddr,  //36:32
                       rf_wdata   //31:0
                      };

// this inst is to write reg(gr_we) and it's valid!!
assign ws_to_ds_dest = {5{ws_gr_we && ws_valid}} & ws_dest;
assign ws_to_ds_value = {32{ws_gr_we && ws_valid}} & rf_wdata;

assign ws_ready_go = 1'b1;
assign ws_allowin  = !ws_valid || ws_ready_go;

always @(posedge clk) begin
    if (reset) begin
        ws_valid <= 1'b0;
    end
    else if(ws_reflush_ds) begin
        ws_valid <= 1'b0;
    end
    else if (ws_allowin) begin
        ws_valid <= ms_to_ws_valid;
    end
end

always @(posedge clk) begin
    if (ms_to_ws_valid && ws_allowin) begin
        ms_to_ws_bus_r <= ms_to_ws_bus;
    end
end

assign rf_we    = ws_gr_we && ws_valid;
assign rf_waddr = ws_dest;
assign rf_wdata = ws_csr_rd ? csr_rvalue : ws_rdcntid ? csr_rvalue : ws_final_result;

// debug
assign debug_wb_pc       = ws_pc;
assign debug_wb_rf_wen   = {4{rf_we}};
assign debug_wb_rf_wnum  = ws_dest;
assign debug_wb_rf_wdata = rf_wdata;

// csr
wire [31:0] csr_tlbrentry_rvalue;
assign ws_ex = ws_valid & (|ws_ex_cause_bus[15:0]); // ex不包括最新的16号伪异常
assign ws_ecode = (ws_ex_cause_bus[6'h2] & ws_valid) ? `ECODE_ADE   // if异常
                : (ws_ex_cause_bus[6'h1] & ws_valid) ? `ECODE_SYS
                : (ws_ex_cause_bus[6'h3] & ws_valid) ? `ECODE_ALE
                : (ws_ex_cause_bus[6'h4] & ws_valid) ? `ECODE_BRK
                : (ws_ex_cause_bus[6'h5] & ws_valid) ? `ECODE_INE
                : (ws_ex_cause_bus[6'h8] & ws_valid) ? `ECODE_PIS
                : (ws_ex_cause_bus[6'h7] & ws_valid) ? `ECODE_PPI 
                : (ws_ex_cause_bus[6'h6] & ws_valid) ? `ECODE_PME
                : (ws_ex_cause_bus[6'h9] & ws_valid) ? `ECODE_PIL
                : (ws_ex_cause_bus[6'ha] & ws_valid) ? `ECODE_PIF
                : (ws_ex_cause_bus[6'hd] & ws_valid) ? `ECODE_ADE   // exe异常
                : (ws_ex_cause_bus[6'hb] & ws_valid) ? `ECODE_TLBR
                : 6'b0;                     // !!!!! 只记录最早报出的例外
assign ws_esubcode = (ws_ex_cause_bus[6'h2] & ws_valid) ? `ESUBCODE_ADEF
                    : (ws_ex_cause_bus[6'hd] & ws_valid) ? `ESUBCODE_ADEM
                    : 9'b0;
assign ws_reflush_ds = ws_valid & // valid stage
                    ( ws_ertn // ertn happened or
                    | (|ws_ex_cause_bus) // there are some exception causes
                    | (ws_csr_we & (ws_csr_num== `CSR_CRMD || ws_csr_num == `CSR_DMW0 || ws_csr_num==`CSR_DMW1 || ws_csr_num==`CSR_ASID)) // 写对应寄存器
                    );
assign ws_reflush_es = ws_reflush_ds;
assign ws_reflush_ms = ws_reflush_ds;
assign ws_reflush_fs_bus = {ws_reflush_ds, // 有ertn或者有中断，则需flush
                        ws_ertn ? era_entry :// ertn 恢复, 后面需要单独判定第16位
                        // ( ws_ex_cause_bus[16] ? ws_pc: ((|ws_ex_cause_bus[15:0])?(ex_entry):{ws_pc}+4) )
                        ((|ws_ex_cause_bus[15:0])?((ws_ecode==`ECODE_TLBR)?csr_tlbrentry_rvalue:ex_entry):{ws_pc}+4)
                        };     
assign hw_int_in     = 8'b0;            // ????? 这个硬中断如何采样处理？
assign ipi_int_in    = 1'b0;
assign ws_csr = (ws_csr_we || ws_csr_rd) & ws_valid;
assign coreid_in = 32'b0;

// exp18
/*
 * 和exe阶段的srch交互, 具体见exe文件
 */

// wire [4 : 0] tlb_bus; //tlbsrch,tlbrd,tlbwr,tlbfill,invtlb
wire tlbsrch_hit;
wire [31: 0] srch_tlbidx_wvalue;
wire [31: 0] rd_tlbidx_wvalue;
wire [31: 0] csr_tlbidx_wvalue;
wire [31: 0] csr_tlbehi_wvalue;
wire [31: 0] csr_tlbelo0_wvalue;
wire [31: 0] csr_tlbelo1_wvalue;
wire [31: 0] csr_asid_wvalue;
wire [31: 0] csr_tlbidx_rvalue;
wire [31: 0] csr_tlbehi_rvalue;
wire [31: 0] csr_tlbelo0_rvalue;
wire [31: 0] csr_tlbelo1_rvalue;
wire [31: 0]csr_asid_rvalue;
wire [31: 0] csr_crmd_rvalue;
wire [31: 0] csr_dmw0_rvalue;
wire [31: 0] csr_dmw1_rvalue;
wire [31: 0] csr_estat_rvalue;
wire [31: 0] ex_tlb_entry;
wire csr_tlbrd_re;
wire srch_valid; // 为了标志是srch指令, 区分开未命中的
wire [4:0] srch_bus; // ! 为了传入exe阶段的tlb操作, 用来改写tlb_bus

assign ws_to_es_bus = {csr_tlbehi_rvalue, csr_crmd_rvalue, csr_dmw0_rvalue, csr_dmw1_rvalue, csr_asid_rvalue};
assign ws_to_fs_bus = {csr_crmd_rvalue, csr_dmw0_rvalue, csr_dmw1_rvalue, csr_asid_rvalue};
assign {srch_valid, tlbsrch_hit, srch_bus, srch_tlbidx_wvalue} = to_ws_csr_bus;
assign tlb_bus = ({5{ws_valid && (~|ws_ex_cause_bus)}} & ws_tlb_bus) | ({5{srch_valid}} & srch_bus);

/*
 TODO: 处理WR FILL RD指令
 ! inst_tlbsrch, inst_tlbrd, inst_tlbwr, inst_tlbfill, inst_invtlb bus顺序, 4-0
 * WR指令--2
    * 从CSR.TLBEHI, CSR.TLBELO0, CSR.TLBELO1, CSR.TLBIDX.PS
    * 详细内容见下
 * FILL 一致
 * RD指令--3
 */

assign we = tlb_bus[1] || tlb_bus[2]; // fill or wr
assign w_index = we ? csr_tlbidx_rvalue[3:0] : 4'b0;
assign w_e = /*(csr_estat_rvalue[21:16]==6'h3f) ||*/ ~csr_tlbidx_rvalue[31];
assign w_ps = csr_tlbidx_rvalue[29:24];
assign w_vppn = csr_tlbehi_rvalue[31:13];
assign w_asid = csr_asid_rvalue[9:0];
assign w_g = csr_tlbelo1_rvalue[6] & csr_tlbelo0_rvalue[6]; 
assign w_ppn0 = csr_tlbelo0_rvalue[31:8];
assign w_plv0 = csr_tlbelo0_rvalue[3:2];
assign w_mat0 = csr_tlbelo0_rvalue[5:4];
assign w_d0 = csr_tlbelo0_rvalue[1];
assign w_v0 = csr_tlbelo0_rvalue[0];
assign w_ppn1 = csr_tlbelo1_rvalue [31:8];
assign w_plv1 = csr_tlbelo1_rvalue [3:2];
assign w_mat1 = csr_tlbelo1_rvalue [5:4];
assign w_d1 = csr_tlbelo1_rvalue [1];
assign w_v1 = csr_tlbelo1_rvalue [0];
// 读端口
assign r_index = csr_tlbidx_rvalue[3:0];
assign csr_tlbrd_re = r_e & ws_valid & ~|ws_ex_cause_bus;
assign csr_tlbehi_wvalue = {r_vppn,13'b0 };
assign rd_tlbidx_wvalue = { ~r_e, 1'b0, r_ps, 20'b0, r_index};
assign csr_tlbidx_wvalue = tlb_bus[3]? rd_tlbidx_wvalue : srch_tlbidx_wvalue;
assign csr_asid_wvalue[9:0] = r_asid;
assign csr_tlbelo0_wvalue = {r_ppn0,1'b0,r_g,r_mat0,r_plv0,r_d0, r_v0};
assign csr_tlbelo1_wvalue = {r_ppn1,1'b0,r_g,r_mat1,r_plv1,r_d1, r_v1};

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
    ,.ipi_int_in    (ipi_int_in),
// tlb
    .tlb_bus          (tlb_bus), //tlbsrch,tlbrd,tlbwr,tlbfill,invtlb
    .srch_valid         (srch_valid),
    .tlbsrch_hit        (tlbsrch_hit),
    .csr_tlbrd_re       (csr_tlbrd_re),
    .csr_tlbidx_wvalue  (csr_tlbidx_wvalue),
    .csr_tlbehi_wvalue  (csr_tlbehi_wvalue),
    .csr_tlbelo0_wvalue (csr_tlbelo0_wvalue),
    .csr_tlbelo1_wvalue (csr_tlbelo1_wvalue),
    .csr_asid_wvalue    (csr_asid_wvalue),
    .csr_tlbrentry_rvalue (csr_tlbrentry_rvalue),
    .csr_tlbidx_rvalue  (csr_tlbidx_rvalue),
    .csr_tlbehi_rvalue  (csr_tlbehi_rvalue),
    .csr_tlbelo0_rvalue (csr_tlbelo0_rvalue),
    .csr_tlbelo1_rvalue (csr_tlbelo1_rvalue),
    .csr_asid_rvalue    (csr_asid_rvalue),
    .csr_crmd_rvalue    (csr_crmd_rvalue),
    .csr_dmw0_rvalue    (csr_dmw0_rvalue),
    .csr_dmw1_rvalue    (csr_dmw1_rvalue),
    .csr_estat_rvalue   (csr_estat_rvalue) 
);

endmodule