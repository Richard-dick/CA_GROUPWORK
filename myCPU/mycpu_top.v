module mycpu_top(
    input  wire        clk,
    input  wire        resetn,
    // inst sram interface
    // output wire        inst_sram_en,
    // output wire        inst_sram_we,
    // output wire [31:0] inst_sram_addr,
    // output wire [31:0] inst_sram_wdata,
    // input  wire [31:0] inst_sram_rdata,
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
    // output wire        data_sram_en,
    // output wire [ 3:0] data_sram_we,
    // output wire [31:0] data_sram_addr,
    // output wire [31:0] data_sram_wdata,
    // input  wire [31:0] data_sram_rdata,

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

wire [64:0] fs_to_ds_bus;
wire [231:0] ds_to_es_bus;
wire [143:0] es_to_ms_bus;
wire [168:0] ms_to_ws_bus;
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


IF_stage if_stage(
    .clk               (clk            ),
    .reset             (reset          ),
    .ds_allowin        (ds_allowin     ),
    .br_bus            (br_bus         ),
    .fs_to_ds_valid    (fs_to_ds_valid ),
    .fs_to_ds_bus      (fs_to_ds_bus   ),
    .inst_sram_req     (inst_sram_req  ),
    .inst_sram_wr      (inst_sram_wr   ),  
    .inst_sram_size    (inst_sram_size ),
    .inst_sram_addr    (inst_sram_addr ),
    .inst_sram_wstrb   (inst_sram_wstrb),
    .inst_sram_wdata   (inst_sram_wdata),
    .inst_sram_addr_ok (inst_sram_addr_ok),
    .inst_sram_data_ok (inst_sram_data_ok),
    .inst_sram_rdata   (inst_sram_rdata),
    .ws_reflush_fs_bus (ws_reflush_fs_bus)
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
    .ms_to_ds_data_sram_data_ok (ms_to_ds_data_sram_data_ok),
    .ms_to_ds_res_from_mem (ms_to_ds_res_from_mem),
    .ws_reflush_ds  (ws_reflush_ds),
    .has_int        (has_int),
    // block
    .es_csr         (es_csr),
    .ms_csr         (ms_csr),
    .ws_csr         (ws_csr),
    .es_tid         (es_tid),
    .ms_tid         (ms_tid)
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
    .es_tid         (es_tid)
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
    .ms_to_ds_res_from_mem(ms_to_ds_res_from_mem),
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

    .has_int          (has_int),
    .ws_csr         (ws_csr)
);
endmodule
