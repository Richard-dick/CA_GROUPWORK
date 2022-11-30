module cpu_core
#(
    parameter TLBNUM = 16
)
(
    input  wire        clk,
    input  wire        resetn,

    // inst sram interface
    output wire        inst_sram_req,   //en
    output wire        inst_sram_wr,    //|wen
    output wire [ 1:0] inst_sram_size, 
    output wire [31:0] inst_sram_addr,
    output wire [ 3:0] inst_sram_wstrb, //wen
    output wire [31:0] inst_sram_wdata,
    input  wire        inst_sram_addr_ok,
    input  wire        inst_sram_data_ok,
    input  wire [31:0] inst_sram_rdata,

    // data sram interface
    output wire        data_sram_req,
    output wire        data_sram_wr,
    output wire [ 1:0] data_sram_size,
    output wire [31:0] data_sram_addr,
    output wire [ 3:0] data_sram_wstrb,
    output wire [31:0] data_sram_wdata,
    input  wire        data_sram_addr_ok,
    input  wire        data_sram_data_ok,
    input  wire [31:0] data_sram_rdata,
    
    // trace debug interface
    output wire [31:0] debug_wb_pc,
    output wire [ 3:0] debug_wb_rf_we,
    output wire [ 4:0] debug_wb_rf_wnum,
    output wire [31:0] debug_wb_rf_wdata
);
wire         reset;
//always @(posedge clk) reset <= ~resetn;
assign reset = ~resetn;


//exp14之前的端口
// wire        inst_sram_en;
// wire        inst_sram_we;
// wire [31:0] inst_sram_addr;
// wire [31:0] inst_sram_wdata;
// wire [31:0] inst_sram_rdata;
// wire        data_sram_en;
// wire [ 3:0] data_sram_we;
// wire [31:0] data_sram_addr;
// wire [31:0] data_sram_wdata;
// wire [31:0] data_sram_rdata;

wire ds_allowin;
wire es_allowin;
wire ms_allowin;
wire ws_allowin;
wire fs_to_ds_valid;
wire ds_to_es_valid;
wire es_to_ms_valid;
wire ms_to_ws_valid;

wire [69:0] fs_to_ds_bus;
wire [241:0] ds_to_es_bus;
wire [148:0] es_to_ms_bus;
wire [173:0] ms_to_ws_bus;
wire [37:0] ws_to_rf_bus;
wire [33:0] br_bus;

wire [4:0] es_to_ds_dest;
wire [4:0] ms_to_ds_dest;
wire [4:0] ws_to_ds_dest;

wire [31:0] es_to_ds_value;
wire [31:0] ms_to_ds_value;
wire [31:0] ws_to_ds_value;

wire es_value_from_mem;

wire [32:0] ws_reflush_fs_bus;
wire ws_reflush_ds;
wire ws_reflush_es;
wire ws_reflush_ms;
wire has_int;
wire es_csr;
wire ms_csr;
wire ws_csr;
wire ms_int;

wire ms_to_ds_data_sram_data_ok;

// ! exp18
// 新加的, 和TLB相连的端口:: 端口作用详见tlb.v
// ! 指令端口
wire [              18:0]    s0_vppn;
wire                         s0_va_bit12;
wire [               9:0]    s0_asid;
wire                         s0_found;
wire [$clog2(TLBNUM)-1:0]    s0_index;
wire [              19:0]    s0_ppn;
wire [               5:0]    s0_ps;
wire [               1:0]    s0_plv;
wire [               1:0]    s0_mat;
wire                         s0_d;
wire                         s0_v;
// ! 访存端口
wire  [              18:0]   s1_vppn;
wire                         s1_va_bit12;
wire  [               9:0]   s1_asid;
wire                         s1_found;
wire [$clog2(TLBNUM)-1:0]    s1_index;
wire [              19:0]    s1_ppn;
wire [               5:0]    s1_ps;
wire [               1:0]    s1_plv;
wire [               1:0]    s1_mat;
wire                         s1_d;
wire                         s1_v;
// 清除无效的TLB表项指令 支持
wire                         invtlb_valid;
wire  [               4:0]   invtlb_op;
// * 支持TLBWR和TLBFILL指令
wire                         we;
wire  [$clog2(TLBNUM)-1:0]   w_index;
wire                         w_e;
wire  [               5:0]   w_ps;
wire  [              18:0]   w_vppn;
wire  [               9:0]   w_asid;
wire                         w_g;
wire  [              19:0]   w_ppn0;
wire  [               1:0]   w_plv0;
wire  [               1:0]   w_mat0;
wire                         w_d0;
wire                         w_v0;
wire  [              19:0]   w_ppn1;
wire  [               1:0]   w_plv1;
wire  [               1:0]   w_mat1;
wire                         w_d1;
wire                         w_v1;
// 支持TLB读指令
wire  [$clog2(TLBNUM)-1:0]   r_index;
wire                         r_e;
wire [              18:0]    r_vppn;
wire [               5:0]    r_ps;
wire [               9:0]    r_asid;
wire                         r_g;
wire [              19:0]    r_ppn0;
wire [               1:0]    r_plv0;
wire [               1:0]    r_mat0;
wire                         r_d0;
wire                         r_v0;
wire [              19:0]    r_ppn1;     
wire [               1:0]    r_plv1;
wire [               1:0]    r_mat1;
wire                         r_d1;
wire                         r_v1;

// exe和wb的csr, srch交互
wire [63:0] to_es_tlb_bus;
wire [38:0] to_ws_csr_bus;

// id--> if is tlb inst
wire is_tlb;

// exp19
wire [127:0] ws_to_fs_bus;
wire [159:0] ws_to_es_bus;

IF_stage if_stage(
    .clk                (clk            ),
    .reset              (reset          ),
    .ds_allowin         (ds_allowin     ),
    .br_bus             (br_bus         ),
    .fs_to_ds_valid     (fs_to_ds_valid ),
    .fs_to_ds_bus       (fs_to_ds_bus   ),
    .inst_sram_req      (inst_sram_req  ),
    .inst_sram_wr       (inst_sram_wr   ),  
    .inst_sram_size     (inst_sram_size ),
    .inst_sram_addr     (inst_sram_addr ),
    .inst_sram_wstrb    (inst_sram_wstrb),
    .inst_sram_wdata    (inst_sram_wdata),
    .inst_sram_addr_ok  (inst_sram_addr_ok),
    .inst_sram_data_ok  (inst_sram_data_ok),
    .inst_sram_rdata    (inst_sram_rdata),
    .ws_reflush_fs_bus  (ws_reflush_fs_bus),
    .ws_to_fs_bus       (ws_to_fs_bus),
    // connect with TLB
    .s0_vppn            (s0_vppn        ),
    .s0_va_bit12        (s0_va_bit12    ),
    .s0_asid            (s0_asid        ),
    .s0_found           (s0_fount       ),
    .s0_index           (s0_index       ),
    .s0_ppn             (s0_ppn         ),  
    .s0_ps              (s0_ps          ),
    .s0_plv             (s0_plv         ),
    .s0_mat             (s0_mat         ),
    .s0_d               (s0_d           ),
    .s0_v               (s0_v           )
);


ID_stage id_stage(
    .clk            (clk            ),
    .reset          (reset          ),
    .es_allowin     (es_allowin     ),
    .ds_allowin     (ds_allowin     ),
    .fs_to_ds_valid (fs_to_ds_valid ),
    .fs_to_ds_bus   (fs_to_ds_bus   ),
    .ds_to_es_valid (ds_to_es_valid ),
    .ds_to_es_bus   (ds_to_es_bus   ),
    .br_bus         (br_bus         ),
    .ws_to_rf_bus   (ws_to_rf_bus   ),
    .es_to_ds_dest  (es_to_ds_dest  ),
    .ms_to_ds_dest  (ms_to_ds_dest  ),
    .ws_to_ds_dest  (ws_to_ds_dest  ),
    .es_to_ds_value (es_to_ds_value ),
    .ms_to_ds_value (ms_to_ds_value ),
    .ws_to_ds_value (ws_to_ds_value ),
    .es_value_from_mem (es_value_from_mem),
    .ms_to_ds_data_sram_data_ok(ms_to_ds_data_sram_data_ok),
    .ms_to_ds_res_from_mem (ms_to_ds_res_from_mem),
    .ws_reflush_ds  (ws_reflush_ds),
    .has_int        (has_int),
    // block
    .es_csr         (es_csr),
    .ms_csr         (ms_csr),
    .ws_csr         (ws_csr),
    .es_tid         (es_tid),
    .ms_tid         (ms_tid),
    .is_tlb         (is_tlb)
);

EXE_stage exe_stage(
    .clk            (clk            ),
    .reset          (reset          ),
    .ms_allowin     (ms_allowin     ),
    .es_allowin     (es_allowin     ),
    .ds_to_es_valid (ds_to_es_valid ),
    .ds_to_es_bus   (ds_to_es_bus   ),
    .es_to_ms_valid (es_to_ms_valid ),
    .es_to_ms_bus   (es_to_ms_bus   ),
    .data_sram_req  (data_sram_req  ),
    .data_sram_wr   (data_sram_wr   ),
    .data_sram_size (data_sram_size ),
    .data_sram_addr (data_sram_addr ),
    .data_sram_wstrb(data_sram_wstrb),
    .data_sram_wdata(data_sram_wdata),
    .data_sram_addr_ok(data_sram_addr_ok),
    .es_to_ds_dest  (es_to_ds_dest  ),
    .es_to_ds_value (es_to_ds_value ),
    .es_value_from_mem (es_value_from_mem),
    .ws_reflush_es  (ws_reflush_es),
    .ms_int         (ms_int),
    .es_csr         (es_csr),
    .es_tid         (es_tid),
    // TLB
    .s1_vppn       (s1_vppn        ),
    .s1_va_bit12   (s1_va_bit12    ),
    .s1_asid       (s1_asid        ),
    .s1_found      (s1_found       ),
    .s1_index      (s1_index       ),
    .s1_ppn        (s1_ppn         ),
    .s1_ps         (s1_ps          ),
    .s1_plv        (s1_plv         ),
    .s1_mat        (s1_mat         ),
    .s1_d          (s1_d           ),
    .s1_v          (s1_v           ),
    // 清楚无效的TLB表项指令 in EXE
    .invtlb_valid  (invtlb_valid   ),
    .invtlb_op     (invtlb_op      ),
    // exe和wb的csr, srch交互
    // .to_es_tlb_bus (to_es_tlb_bus  ),
    .to_ws_csr_bus (to_ws_csr_bus  ),
    .ws_to_es_bus       (ws_to_es_bus),
    .is_tlb             (is_tlb         )
);

MEM_stage mem_stage(
    .clk            (clk            ),
    .reset          (reset          ),
    .ws_allowin     (ws_allowin     ),
    .ms_allowin     (ms_allowin     ),
    .es_to_ms_valid (es_to_ms_valid ),
    .es_to_ms_bus   (es_to_ms_bus   ),
    .ms_to_ws_valid (ms_to_ws_valid ),
    .ms_to_ws_bus   (ms_to_ws_bus   ),
    .data_sram_rdata(data_sram_rdata),
    .data_sram_data_ok(data_sram_data_ok),
    .ms_to_ds_dest  (ms_to_ds_dest  ),
    .ms_to_ds_value (ms_to_ds_value ),
    .ms_to_ds_data_sram_data_ok(ms_to_ds_data_sram_data_ok),
    .ms_to_ds_res_from_mem (ms_to_ds_res_from_mem),
    .ws_reflush_ms  (ws_reflush_ms),
    .ms_int         (ms_int),
    .ms_csr         (ms_csr),
    .ms_tid         (ms_tid)
);

WB_stage wb_stage(
    .clk            (clk            ),
    .reset          (reset          ),
    .ws_allowin     (ws_allowin     ),
    .ms_to_ws_valid (ms_to_ws_valid ),
    .ms_to_ws_bus   (ms_to_ws_bus   ),
    .ws_to_rf_bus   (ws_to_rf_bus   ),
    // debug
    .debug_wb_pc      (debug_wb_pc      ),
    .debug_wb_rf_wen  (debug_wb_rf_we   ),
    .debug_wb_rf_wnum (debug_wb_rf_wnum ),
    .debug_wb_rf_wdata(debug_wb_rf_wdata),
    .ws_to_ds_dest    (ws_to_ds_dest    ),
    .ws_to_ds_value   (ws_to_ds_value   ),
    // exception
    .ws_reflush_fs_bus(ws_reflush_fs_bus),
    .ws_reflush_ds    (ws_reflush_ds),
    .ws_reflush_es    (ws_reflush_es),
    .ws_reflush_ms    (ws_reflush_ms),

    .ws_to_fs_bus       (ws_to_fs_bus),
    .ws_to_es_bus       (ws_to_es_bus),

    .has_int          (has_int),
    .ws_csr           (ws_csr),
    // * 支持TLBWR和TLBFILL指令 in WB
    .we            (we             ),
    .w_index       (w_index        ),
    .w_e           (w_e            ),
    .w_ps          (w_ps           ),
    .w_vppn        (w_vppn         ),
    .w_asid        (w_asid         ),
    .w_g           (w_g            ),
    .w_ppn0        (w_ppn0         ),
    .w_plv0        (w_plv0         ),
    .w_mat0        (w_mat0         ),
    .w_d0          (w_d0           ),
    .w_v0          (w_v0           ),
    .w_ppn1        (w_ppn1         ),
    .w_plv1        (w_plv1         ),
    .w_mat1        (w_mat1         ),
    .w_d1          (w_d1           ),
    .w_v1          (w_v1           ),
    // 支持TLB读指令 in WB
    .r_index       (r_index        ),
    .r_e           (r_e            ),
    .r_vppn        (r_vppn         ),
    .r_ps          (r_ps           ),
    .r_asid        (r_asid         ),
    .r_g           (r_g            ),
    .r_ppn0        (r_ppn0         ),
    .r_plv0        (r_plv0         ),
    .r_mat0        (r_mat0         ),
    .r_d0          (r_d0           ),
    .r_v0          (r_v0           ),
    .r_ppn1        (r_ppn1         ),
    .r_plv1        (r_plv1         ),
    .r_mat1        (r_mat1         ),
    .r_d1          (r_d1           ),
    .r_v1          (r_v1           ),
    // exe和wb的csr, srch交互
    // .to_es_tlb_bus (to_es_tlb_bus  ),
    .to_ws_csr_bus (to_ws_csr_bus  )
);

tlb tlb(
    .clk           (clk            ),
    // ! 指令端口, in IF
    .s0_vppn       (s0_vppn        ),
    .s0_va_bit12   (s0_va_bit12    ),
    .s0_asid       (s0_asid        ),
    .s0_found      (s0_fount       ),
    .s0_index      (s0_index       ),
    .s0_ppn        (s0_ppn         ),  
    .s0_ps         (s0_ps          ),
    .s0_plv        (s0_plv         ),
    .s0_mat        (s0_mat         ),
    .s0_d          (s0_d           ),
    .s0_v          (s0_v           ),
    // ! 访存端口 in EXE
    .s1_vppn       (s1_vppn        ),
    .s1_va_bit12   (s1_va_bit12    ),
    .s1_asid       (s1_asid        ),
    .s1_found      (s1_found       ),
    .s1_index      (s1_index       ),
    .s1_ppn        (s1_ppn         ),
    .s1_ps         (s1_ps          ),
    .s1_plv        (s1_plv         ),
    .s1_mat        (s1_mat         ),
    .s1_d          (s1_d           ),
    .s1_v          (s1_v           ),
    // 清楚无效的TLB表项指令 in EXE
    .invtlb_valid  (invtlb_valid   ),
    .invtlb_op     (invtlb_op      ),
    // * 支持TLBWR和TLBFILL指令 in WB
    .we            (we             ), 
    .w_index       (w_index        ),
    .w_e           (w_e            ),
    .w_ps          (w_ps           ),
    .w_vppn        (w_vppn         ),
    .w_asid        (w_asid         ),
    .w_g           (w_g            ),
    .w_ppn0        (w_ppn0         ),
    .w_plv0        (w_plv0         ),
    .w_mat0        (w_mat0         ),
    .w_d0          (w_d0           ),
    .w_v0          (w_v0           ),
    .w_ppn1        (w_ppn1         ),
    .w_plv1        (w_plv1         ),
    .w_mat1        (w_mat1         ),
    .w_d1          (w_d1           ),
    .w_v1          (w_v1           ),
    // 支持TLB读指令 in WB
    .r_index       (r_index        ),
    .r_e           (r_e            ),
    .r_vppn        (r_vppn         ),
    .r_ps          (r_ps           ),
    .r_asid        (r_asid         ),
    .r_g           (r_g            ),
    .r_ppn0        (r_ppn0         ),
    .r_plv0        (r_plv0         ),
    .r_mat0        (r_mat0         ),
    .r_d0          (r_d0           ),
    .r_v0          (r_v0           ),
    .r_ppn1        (r_ppn1         ),     
    .r_plv1        (r_plv1         ),
    .r_mat1        (r_mat1         ),
    .r_d1          (r_d1           ),
    .r_v1          (r_v1           )
);

endmodule
