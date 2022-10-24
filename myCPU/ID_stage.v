module ID_stage(
    input          clk,
    input          reset,
    //allowin
    input          es_allowin,
    output         ds_allowin,
    //from fs
    input          fs_to_ds_valid,
    input  [64:0]  fs_to_ds_bus,
    //to es
    output         ds_to_es_valid,
    output [231:0] ds_to_es_bus,
    //to fs
    output [32:0]  br_bus,
    //to rf: for write back
    input  [37:0]  ws_to_rf_bus,
    //from latter stages: to cancel an inst by revising ready_go
    input  [ 4:0]  es_to_ds_dest,
    input  [ 4:0]  ms_to_ds_dest,
    input  [ 4:0]  ws_to_ds_dest,

    input  [31:0]  es_to_ds_value,
    input  [31:0]  ms_to_ds_value,
    input  [31:0]  ws_to_ds_value,

    input          es_value_from_mem,
    //reflush
    input          ws_reflush_ds,
    //int 
    input          has_int,
    // block
    input          es_csr,
    input          ms_csr,
    input          ws_csr
);

reg         ds_valid;
wire        ds_ready_go;

reg  [64:0] fs_to_ds_bus_r;

wire [31:0] ds_inst;
wire [31:0] ds_pc;

wire [ 4:0] rf_raddr1;
wire [31:0] rf_rdata1;
wire [ 4:0] rf_raddr2;
wire [31:0] rf_rdata2;
wire        rf_we;
wire [ 4:0] rf_waddr;
wire [31:0] rf_wdata;

wire        br_taken;
wire [31:0] br_target;

wire [11:0] alu_op;
wire [6 :0] mul_div_op;
wire [7 :0] ld_st_op;
wire        src1_is_pc;
wire        src2_is_imm;
wire        res_from_mem;
wire        gr_we;
wire        mem_we;
wire        src_reg_is_rd;
wire [4: 0] dest;
wire [31:0] rj_value;
wire [31:0] rkd_value;
wire [31:0] imm;
wire [31:0] br_offs;
wire [31:0] jirl_offs;
wire        dst_is_r1;

//define
wire [ 5:0] op_31_26;
wire [ 3:0] op_25_22;
wire [ 1:0] op_21_20;
wire [ 4:0] op_19_15;
wire [ 4:0] rd;
wire [ 4:0] rj;
wire [ 4:0] rk;
wire [11:0] i12;
wire [19:0] i20;
wire [15:0] i16;
wire [25:0] i26;

wire        need_ui5;
wire        need_ui12;
wire        need_si12;
wire        need_si16;
wire        need_si20;
wire        need_si26;
wire        src2_is_4;

wire [63:0] op_31_26_d;
wire [15:0] op_25_22_d;
wire [ 3:0] op_21_20_d;
wire [31:0] op_19_15_d;

wire        inst_add_w;
wire        inst_sub_w;
wire        inst_slt;
wire        inst_sltu;
wire        inst_nor;
wire        inst_and;
wire        inst_or;
wire        inst_xor;
wire        inst_slli_w;
wire        inst_srli_w;
wire        inst_srai_w;
wire        inst_addi_w;
wire        inst_ld_w;
wire        inst_st_w;
wire        inst_jirl;
wire        inst_b;
wire        inst_bl;
wire        inst_beq;
wire        inst_bne;
wire        inst_lu12i_w;
wire        inst_slti;
wire        inst_sltui;
wire        inst_andi;
wire        inst_ori;
wire        inst_xori;
wire        inst_sll;
wire        inst_srl;
wire        inst_sra;
wire        inst_pcaddu12i;
wire        inst_mul_w;
wire        inst_mulh_w;
wire        inst_mulh_wu;
wire        inst_div_w;
wire        inst_mod_w;
wire        inst_mod_wu;
wire        inst_div_wu;
wire        inst_blt;
wire        inst_bge;
wire        inst_bltu;
wire        inst_bgeu;
wire        inst_ld_b;
wire        inst_ld_bu;
wire        inst_ld_h;
wire        inst_ld_hu;
wire        inst_st_b;
wire        inst_st_h;
wire        inst_rdcntvl_w;
wire        inst_rdcntvh_w;
wire        inst_rdcntid_w;

// 用于RDCNT类3条指令特殊译码
wire        inst_rdcnt;
wire        inst_rdcntvl_w_tail;
wire        inst_rdcntvh_w_tail;
wire        inst_rdcntid_w_tail;

// exp12 - kernel mode
wire csr_we;
wire csr_rd;
wire [31:0] csr_wmask;
wire [13:0] csr_num;
wire        inst_csr_rd;
wire        inst_csr_wr;
wire        inst_csr_xchg;
wire        inst_ertn;
wire        inst_syscall;
wire        inst_break;
wire [16:0] ex_cause_bus;

// exp13 - exception judgment logic signals
wire ex_adef;       // 取指地址错 (由fs_to_ex_bus搭载)
wire ex_ine;        // 指令不存在

// data block signal
wire        rf_addr1_raw;
wire        rf_addr2_raw;
wire [31:0] rf_addr1_forward;
wire [31:0] rf_addr2_forward;
wire        es_ld_cancel;
reg         es_rdcntid_cancel_stall;
wire        es_rdcntid_cancel;
wire        es_cancel;
wire        es_crash;//说明es阶段的dest和当前写相同，这种情况下，才考虑ready_go调0
wire        ms_crash;
wire        csr_block;
wire        es_csr_block;
wire        ms_csr_block;
wire        ws_csr_block;

// 讲义7.4 计数器相关的三条指令
wire rdcntvl;
wire rdcntvh;
wire rdcntid;

// branch instrutions
wire rj_eq_rd;
wire rj_l_rd;
wire rj_ge_rd;
wire rj_l_rd_u;
wire rj_ge_rd_u;

assign op_31_26  = ds_inst[31:26];
assign op_25_22  = ds_inst[25:22];
assign op_21_20  = ds_inst[21:20];
assign op_19_15  = ds_inst[19:15];

assign rd   = ds_inst[ 4: 0];
assign rj   = ds_inst[ 9: 5];
assign rk   = ds_inst[14:10];

assign i12  = ds_inst[21:10];
assign i20  = ds_inst[24: 5];
assign i16  = ds_inst[25:10];
assign i26  = {ds_inst[ 9: 0], ds_inst[25:10]};

decoder_6_64 u_dec0(.in(op_31_26 ), .out(op_31_26_d ));
decoder_4_16 u_dec1(.in(op_25_22 ), .out(op_25_22_d ));
decoder_2_4  u_dec2(.in(op_21_20 ), .out(op_21_20_d ));
decoder_5_32 u_dec3(.in(op_19_15 ), .out(op_19_15_d ));

assign inst_add_w  = op_31_26_d[6'h00] & op_25_22_d[4'h0] & op_21_20_d[2'h1] & op_19_15_d[5'h00];
assign inst_sub_w  = op_31_26_d[6'h00] & op_25_22_d[4'h0] & op_21_20_d[2'h1] & op_19_15_d[5'h02];
assign inst_slt    = op_31_26_d[6'h00] & op_25_22_d[4'h0] & op_21_20_d[2'h1] & op_19_15_d[5'h04];
assign inst_sltu   = op_31_26_d[6'h00] & op_25_22_d[4'h0] & op_21_20_d[2'h1] & op_19_15_d[5'h05];
assign inst_nor    = op_31_26_d[6'h00] & op_25_22_d[4'h0] & op_21_20_d[2'h1] & op_19_15_d[5'h08];
assign inst_and    = op_31_26_d[6'h00] & op_25_22_d[4'h0] & op_21_20_d[2'h1] & op_19_15_d[5'h09];
assign inst_or     = op_31_26_d[6'h00] & op_25_22_d[4'h0] & op_21_20_d[2'h1] & op_19_15_d[5'h0a];
assign inst_xor    = op_31_26_d[6'h00] & op_25_22_d[4'h0] & op_21_20_d[2'h1] & op_19_15_d[5'h0b];
assign inst_slli_w = op_31_26_d[6'h00] & op_25_22_d[4'h1] & op_21_20_d[2'h0] & op_19_15_d[5'h01];
assign inst_srli_w = op_31_26_d[6'h00] & op_25_22_d[4'h1] & op_21_20_d[2'h0] & op_19_15_d[5'h09];
assign inst_srai_w = op_31_26_d[6'h00] & op_25_22_d[4'h1] & op_21_20_d[2'h0] & op_19_15_d[5'h11];
assign inst_addi_w = op_31_26_d[6'h00] & op_25_22_d[4'ha];
assign inst_ld_w   = op_31_26_d[6'h0a] & op_25_22_d[4'h2];
assign inst_st_w   = op_31_26_d[6'h0a] & op_25_22_d[4'h6];
assign inst_jirl   = op_31_26_d[6'h13];
assign inst_b      = op_31_26_d[6'h14];
assign inst_bl     = op_31_26_d[6'h15];
assign inst_beq    = op_31_26_d[6'h16];
assign inst_bne    = op_31_26_d[6'h17];
assign inst_lu12i_w= op_31_26_d[6'h05] & ~ds_inst[25];
assign inst_slti   = op_31_26_d[6'h00] & op_25_22_d[4'h8];
assign inst_sltui  = op_31_26_d[6'h00] & op_25_22_d[4'h9];
assign inst_andi   = op_31_26_d[6'h00] & op_25_22_d[4'hd];
assign inst_ori    = op_31_26_d[6'h00] & op_25_22_d[4'he];
assign inst_xori   = op_31_26_d[6'h00] & op_25_22_d[4'hf];
assign inst_sll    = op_31_26_d[6'h00] & op_25_22_d[4'h0] & op_21_20_d[2'h1] & op_19_15_d[5'h0e];
assign inst_srl    = op_31_26_d[6'h00] & op_25_22_d[4'h0] & op_21_20_d[2'h1] & op_19_15_d[5'h0f];
assign inst_sra    = op_31_26_d[6'h00] & op_25_22_d[4'h0] & op_21_20_d[2'h1] & op_19_15_d[5'h10];
assign inst_pcaddu12i = op_31_26_d[6'h07] & ~ds_inst[25];
assign inst_mul_w  = op_31_26_d[6'h00] & op_25_22_d[4'h0] & op_21_20_d[2'h1] & op_19_15_d[5'h18];
assign inst_mulh_w = op_31_26_d[6'h00] & op_25_22_d[4'h0] & op_21_20_d[2'h1] & op_19_15_d[5'h19];
assign inst_mulh_wu= op_31_26_d[6'h00] & op_25_22_d[4'h0] & op_21_20_d[2'h1] & op_19_15_d[5'h1a];
assign inst_div_w  = op_31_26_d[6'h00] & op_25_22_d[4'h0] & op_21_20_d[2'h2] & op_19_15_d[5'h00];
assign inst_mod_w  = op_31_26_d[6'h00] & op_25_22_d[4'h0] & op_21_20_d[2'h2] & op_19_15_d[5'h01];
assign inst_div_wu = op_31_26_d[6'h00] & op_25_22_d[4'h0] & op_21_20_d[2'h2] & op_19_15_d[5'h02];
assign inst_mod_wu = op_31_26_d[6'h00] & op_25_22_d[4'h0] & op_21_20_d[2'h2] & op_19_15_d[5'h03];

assign inst_ld_b   = op_31_26_d[6'h0a] & op_25_22_d[4'h0];
assign inst_ld_bu  = op_31_26_d[6'h0a] & op_25_22_d[4'h8];
assign inst_ld_h   = op_31_26_d[6'h0a] & op_25_22_d[4'h1];
assign inst_ld_hu  = op_31_26_d[6'h0a] & op_25_22_d[4'h9];
assign inst_st_b   = op_31_26_d[6'h0a] & op_25_22_d[4'h4];
assign inst_st_h   = op_31_26_d[6'h0a] & op_25_22_d[4'h5];
assign inst_blt    = op_31_26_d[6'h18];
assign inst_bge    = op_31_26_d[6'h19];
assign inst_bltu   = op_31_26_d[6'h1a];
assign inst_bgeu   = op_31_26_d[6'h1b];

// exp12 - kernel inst decoder
assign inst_csr_rd   = op_31_26_d[6'h01] & ~ds_inst[25] & ~ds_inst[24] & ~|rj;
assign inst_csr_wr   = op_31_26_d[6'h01] & ~ds_inst[25] & ~ds_inst[24] & (rj == 5'b1);
assign inst_csr_xchg = op_31_26_d[6'h01] & ~ds_inst[25] & ~ds_inst[24] & (|rj[4:1]);
assign inst_ertn     = op_31_26_d[6'h01] & op_25_22_d[4'h9] & op_21_20_d[2'h0] & op_19_15_d[5'h10]
                       & (rk == 5'b01110) & ~|rj & ~|rd;
assign inst_syscall  = op_31_26_d[6'h00] & op_25_22_d[4'h0] & op_21_20_d[2'h2] & op_19_15_d[5'h16];
assign inst_break    = op_31_26_d[6'h00] & op_25_22_d[4'h0] & op_21_20_d[2'h2] & op_19_15_d[5'h14];

// rdcnt类指令译码
assign inst_rdcnt    = (ds_inst[31:15] == 17'h0);
assign inst_rdcntid_w_tail = (ds_inst[14:10] == 5'h18 && ds_inst[4:0] == 5'h00);
assign inst_rdcntvl_w_tail = (ds_inst[14:10] == 5'h18 && ds_inst[9:5] == 5'h00);
assign inst_rdcntvh_w_tail = (ds_inst[14:10] == 5'h19 && ds_inst[9:5] == 5'h00);
assign inst_rdcntid_w = inst_rdcnt && inst_rdcntid_w_tail;
assign inst_rdcntvl_w = inst_rdcnt && inst_rdcntvl_w_tail;
assign inst_rdcntvh_w = inst_rdcnt && inst_rdcntvh_w_tail;

assign rdcntvh = inst_rdcntvh_w;
assign rdcntvl = inst_rdcntvl_w;
assign rdcntid = inst_rdcntid_w;

assign csr_we       = inst_csr_wr | inst_csr_xchg;
assign csr_rd       = inst_csr_rd | inst_csr_xchg | inst_csr_wr;
assign csr_wmask    = inst_csr_xchg ? rj_value : 32'hffffffff;
assign csr_num = inst_ertn ? 14'h6 : rdcntid ? 14'h40 : ds_inst[23:10];

// Generate exception cause signals at ID stage(ex_ine and etc.).
// --- NOTE: EVERY TIME A NEW INST IS ADDED, EX_INE SIGNAL SHOULD UPDATE ---
assign ex_ine = ~(inst_add_w || inst_addi_w || inst_and || inst_andi || 
                inst_b || inst_beq || inst_bge || inst_bgeu || inst_bgeu ||
                inst_bl || inst_blt || inst_bltu || inst_bne || inst_break ||
                inst_csr_rd || inst_csr_wr || inst_csr_xchg ||
                inst_div_w || inst_div_wu || inst_ertn || inst_jirl ||
                inst_ld_b || inst_ld_bu || inst_ld_h || inst_ld_hu || 
                inst_ld_w || inst_lu12i_w || 
                inst_mod_w || inst_mod_wu || inst_mul_w || inst_mulh_w || inst_mulh_wu ||
                inst_nor || inst_or || inst_ori || inst_pcaddu12i ||
                inst_sll || inst_slli_w || inst_slt || inst_slti || inst_sltu || inst_sltui ||
                inst_sra || inst_srai_w || inst_srl || inst_srli_w || 
                inst_st_b || inst_st_h || inst_st_w || inst_sub_w || inst_syscall ||
                inst_xor || inst_xori || inst_rdcntid_w || inst_rdcntvh_w || inst_rdcntvl_w);

// 自己好好商讨bus中的位置和相关信息，位宽是足够的。
// 目前bus中搭载的异常标志约定如下：
// 0: INT           1: SYSCALL      2: ADEF
// 3: ALE           4: BRK          5: INE
// 6-16: (RESERVED)
assign ex_cause_bus[16:6] = 15'b0;
assign ex_cause_bus[6'h0/*INT    */] = ds_valid & has_int;
assign ex_cause_bus[6'h1/*SYSCALL*/] = ds_valid & inst_syscall;
// TODO: add ID stage exception causes
assign ex_cause_bus[6'h2/*ADEF   */] = ds_valid & ex_adef;
// (ALE exception will be generated at EXE stage)
assign ex_cause_bus[6'h4/*BRK    */] = ds_valid & inst_break;
assign ex_cause_bus[6'h5/*INE    */] = ds_valid & ex_ine;


assign alu_op[ 0] = inst_add_w | inst_addi_w | inst_ld_b | inst_ld_bu | inst_ld_h 
                    | inst_ld_hu | inst_ld_w | inst_st_b | inst_st_h | inst_st_w
                    | inst_jirl | inst_bl | inst_pcaddu12i;
assign alu_op[ 1] = inst_sub_w;
assign alu_op[ 2] = inst_slt |inst_slti;
assign alu_op[ 3] = inst_sltu | inst_sltui;
assign alu_op[ 4] = inst_and | inst_andi;
assign alu_op[ 5] = inst_nor;
assign alu_op[ 6] = inst_or | inst_ori;
assign alu_op[ 7] = inst_xor | inst_xori;
assign alu_op[ 8] = inst_slli_w | inst_sll;
assign alu_op[ 9] = inst_srli_w | inst_srl;
assign alu_op[10] = inst_srai_w | inst_sra;
assign alu_op[11] = inst_lu12i_w ;

assign mul_div_op[0] = inst_mul_w; 
assign mul_div_op[1] = inst_mulh_w;
assign mul_div_op[2] = inst_mulh_wu;
assign mul_div_op[3] = inst_div_w;
assign mul_div_op[4] = inst_mod_w;
assign mul_div_op[5] = inst_div_wu;
assign mul_div_op[6] = inst_mod_wu;

assign ld_st_op[0] = inst_ld_b;
assign ld_st_op[1] = inst_ld_bu;
assign ld_st_op[2] = inst_ld_h;
assign ld_st_op[3] = inst_ld_hu;
assign ld_st_op[4] = inst_ld_w;
assign ld_st_op[5] = inst_st_b;
assign ld_st_op[6] = inst_st_h;
assign ld_st_op[7] = inst_st_w;

wire [31:0] alu_src1;
wire [31:0] alu_src2;

wire br_taken_cancel;

assign need_ui5   =  inst_slli_w | inst_srli_w | inst_srai_w;
assign need_ui12  =  inst_andi | inst_ori | inst_xori;
// assign need_si12  =  inst_addi_w | inst_ld_w | inst_st_w | inst_slti | inst_sltui;
// assign need_si16  =  inst_jirl | inst_beq | inst_bne;
assign need_si12  =  inst_addi_w | inst_ld_b | inst_ld_bu | inst_ld_h | inst_ld_hu | inst_ld_w
                   | inst_st_b | inst_st_h | inst_st_w | inst_slti | inst_sltui;
assign need_si16  =  inst_jirl | inst_beq | inst_bne | inst_blt | inst_bge | inst_bltu | inst_bgeu;
assign need_si20  =  inst_lu12i_w | inst_pcaddu12i;
assign need_si26  =  inst_b | inst_bl;
assign src2_is_4  =  inst_jirl | inst_bl;

assign imm = src2_is_4 ? 32'h4                      :
             need_ui12 ? {20'h0, i12[11:0]}         :
             need_si20 ? {i20[19:0], 12'b0}         :
/*need_ui5 || need_si12*/{{20{i12[11]}}, i12[11:0]} ;

assign br_offs = need_si26 ? {{ 4{i26[25]}}, i26[25:0], 2'b0} :
                             {{14{i16[15]}}, i16[15:0], 2'b0} ;

assign jirl_offs = {{14{i16[15]}}, i16[15:0], 2'b0};

assign src_reg_is_rd = inst_beq | inst_bne | inst_blt | inst_bge 
                    | inst_bltu | inst_bgeu 
                    | inst_st_b | inst_st_h | inst_st_w
                    | inst_csr_wr | inst_csr_xchg;

assign src1_is_pc    = inst_jirl | inst_bl | inst_pcaddu12i;

assign src2_is_imm   = inst_slli_w |
                       inst_srli_w |
                       inst_srai_w |
                       inst_addi_w |
                       inst_ld_w   |
                       inst_st_w   |
                       inst_lu12i_w|
                       inst_jirl   |
                       inst_bl     |
                       inst_slti   |
                       inst_sltui  |
                       inst_andi   |
                       inst_ori    |
                       inst_xori   |
                       inst_pcaddu12i|
                       inst_ld_b   |
                       inst_ld_bu  |
                       inst_ld_h   |
                       inst_ld_hu  |
                       inst_st_b   |
                       inst_st_h   ;

assign res_from_mem  = inst_ld_b | inst_ld_bu 
                    | inst_ld_h | inst_ld_hu | inst_ld_w;
assign dst_is_r1     = inst_bl;
// NOTE: NEWLY ADDED INSTRUCTION MAY DISENABLE GR_WE
assign gr_we         = ~inst_st_b & ~inst_st_h & ~inst_st_w
                     & ~inst_beq & ~inst_bne & ~inst_blt 
                     & ~inst_bge & ~inst_bltu & ~inst_bgeu & ~inst_b;
assign mem_we        = inst_st_b | inst_st_h | inst_st_w;
assign dest          = dst_is_r1 ? 5'd1 : rdcntid ? rj : rd;

assign rf_raddr1 = rj;
assign rf_raddr2 = src_reg_is_rd ? rd :rk;

//data block
assign es_crash = (|es_to_ds_dest)
                && ((rj == es_to_ds_dest)
                || (rk == es_to_ds_dest)
                || (rd == es_to_ds_dest));
assign ms_crash = (|ms_to_ds_dest)
                && ((rj == ms_to_ds_dest)
                || (rk == ms_to_ds_dest)
                || (rd == ms_to_ds_dest));

assign es_csr_block = es_csr && (rf_raddr1 == es_to_ds_dest
                        || rf_raddr2 == es_to_ds_dest);
assign ms_csr_block = ms_csr && (rf_raddr1 == ms_to_ds_dest
                        || rf_raddr2 == ms_to_ds_dest);
assign ws_csr_block = ws_csr && (rf_raddr1 == ws_to_ds_dest
                        || rf_raddr2 == ws_to_ds_dest);

assign rf_addr1_raw = rf_raddr1 && ((rf_raddr1 == es_to_ds_dest)
                || (rf_raddr1 == ms_to_ds_dest)
                || (rf_raddr1 == ws_to_ds_dest));

assign rf_addr2_raw = rf_raddr2 && ((rf_raddr2 == es_to_ds_dest)
                || (rf_raddr2 == ms_to_ds_dest)
                || (rf_raddr2 == ws_to_ds_dest));



assign rf_addr1_forward = rf_raddr1 == es_to_ds_dest ? es_to_ds_value:
                (rf_raddr1 == ms_to_ds_dest ? ms_to_ds_value: 
                (rf_raddr1 == ws_to_ds_dest ? ws_to_ds_value: rf_rdata1));

assign rf_addr2_forward = rf_raddr2 == es_to_ds_dest ? es_to_ds_value:
                (rf_raddr2 == ms_to_ds_dest ? ms_to_ds_value: 
                (rf_raddr2 == ws_to_ds_dest ? ws_to_ds_value: rf_rdata2));

assign rj_value = rf_addr1_raw ? rf_addr1_forward : rf_rdata1;
assign rkd_value = rf_addr2_raw ? rf_addr2_forward : rf_rdata2;

assign rj_eq_rd = (rj_value == rkd_value);
assign rj_l_rd =  (~rj_value[31] && rkd_value[31]) ? 0
                : (rj_value[31] && ~rkd_value[31]) ? 1
                : rj_l_rd_u;
assign rj_ge_rd= ~rj_l_rd;
assign rj_l_rd_u= (rj_value < rkd_value);
assign rj_ge_rd_u= ~rj_l_rd_u;

assign br_taken = (   inst_beq  &&  rj_eq_rd
                   || inst_bne  && !rj_eq_rd
                   || inst_blt  &&  rj_l_rd
                   || inst_bge  &&  rj_ge_rd
                   || inst_bltu &&  rj_l_rd_u
                   || inst_bgeu &&  rj_ge_rd_u
                   || inst_jirl
                   || inst_bl
                   || inst_b
                  ) && ds_valid;
// assign br_target = (inst_beq || inst_bne || inst_bl || inst_b) ? (ds_pc + br_offs) :
//                                                    /*inst_jirl*/ (rj_value + jirl_offs);
assign br_target = (inst_beq || inst_bne || inst_blt || inst_bge || inst_bltu || inst_bgeu || inst_bl || inst_b) 
                                                    ? (ds_pc + br_offs) :
                                                   /*inst_jirl*/ (rj_value + jirl_offs);


assign br_taken_cancel = br_taken && ds_ready_go;

always @(posedge clk) begin
    if (reset)
        ds_valid <= 1'b0;
    else if(br_taken_cancel || ws_reflush_ds)
        ds_valid <= 1'b0;
    else if (ds_allowin)
        ds_valid <= fs_to_ds_valid;
    
end

always @(posedge clk) begin
    if (fs_to_ds_valid && ds_allowin) begin
        fs_to_ds_bus_r <= fs_to_ds_bus;
    end
end

assign br_bus       = {br_taken,br_target};

assign alu_src1 = src1_is_pc  ? ds_pc : rj_value;
assign alu_src2 = src2_is_imm ? imm : rkd_value;

assign ds_to_es_bus = {
    rdcntid,        //231:231
    rdcntvl,        //230:230
    rdcntvh,        //229:229 
    inst_ertn,      //228:228
    csr_we,         //227:227
    csr_rd,         //226:226
    csr_wmask,      //225:194
    csr_num,        //193:180
    ex_cause_bus,   //179:163
    ld_st_op,       //162:155
    mul_div_op,     //154:148
    ds_pc,          //147:116
    alu_op,         //115:104
    alu_src1,       //103:72
    alu_src2,       //71:40
    //mem
    rkd_value,      //39:8
    res_from_mem,   //7:7
    mem_we,         //6:6
    //wb
    dest,           //5:1
    gr_we           //0:0
};

assign es_ld_cancel = !(es_value_from_mem && es_crash);

always @(posedge clk) begin
    if(reset)
        es_rdcntid_cancel_stall <= 1'b1;
    else
        es_rdcntid_cancel_stall <= es_rdcntid_cancel;
end

// rdcntid_stall表示上条指令为rdcntid，用于EXE阶段前递阻塞判断
reg rdcntid_stall;
always @(posedge clk) begin
    if(reset)
        rdcntid_stall <= 1'b0;
    else if(rdcntid_stall == 1'b1)
        rdcntid_stall <= 1'b0;
    else if(rdcntid)
        rdcntid_stall <= 1'b1;
end
// rdcntid_stall表示上条指令为rdcntid，用于MEM阶段前递阻塞判断
reg rdcntid_stall2;
always @(posedge clk) begin
    if(reset)
        rdcntid_stall2 <= 1'b0;
    else if(rdcntid_stall2 == 1'b1)
        rdcntid_stall2 <= 1'b0;
    else if(rdcntid_stall)
        rdcntid_stall2 <= 1'b1;
end
assign es_rdcntid_cancel = !(rdcntid_stall  && es_crash);   
assign ms_rdcntid_cancel = !(rdcntid_stall2 && ms_crash);
assign es_cancel = es_ld_cancel && es_rdcntid_cancel && es_rdcntid_cancel_stall && ms_rdcntid_cancel;

assign csr_block = es_csr_block 
                | ms_csr_block 
                | ws_csr_block;

assign ds_ready_go    = (es_cancel & (!csr_block)) | ws_reflush_ds ;//!(rj_is_raw || rk_is_raw || rd_is_raw);//1'b1;
assign ds_allowin     = !ds_valid || ds_ready_go && es_allowin;
assign ds_to_es_valid = ds_valid && ds_ready_go && !ws_reflush_ds;

assign {ds_inst, ds_pc, ex_adef} = fs_to_ds_bus_r;

assign {rf_we   ,  //37:37
        rf_waddr,  //36:32
        rf_wdata   //31:0
       } = ws_to_rf_bus;

regfile u_regfile(
    .clk    (clk      ),
    .raddr1 (rf_raddr1),
    .rdata1 (rf_rdata1),
    .raddr2 (rf_raddr2),
    .rdata2 (rf_rdata2),
    .we     (rf_we    ),
    .waddr  (rf_waddr ),
    .wdata  (rf_wdata )
    );

endmodule