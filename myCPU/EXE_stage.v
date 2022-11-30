module EXE_stage
#(
    parameter TLBNUM = 16
)
(
    input          clk,
    input          reset,
    //allowin
    input          ms_allowin,
    output         es_allowin,
    //from ds
    input          ds_to_es_valid,
    input  [241:0] ds_to_es_bus,
    //to ms
    output         es_to_ms_valid,
    output [148:0] es_to_ms_bus,
    // data sram interface
    output        data_sram_req,
    output        data_sram_wr,
    output [ 1:0] data_sram_size,
    output [31:0] data_sram_addr,
    output [ 3:0] data_sram_wstrb,
    output [31:0] data_sram_wdata,
    input         data_sram_addr_ok,
    // to ds:: for data block
    output [ 4:0] es_to_ds_dest,
    output [31:0] es_to_ds_value,
    output        es_value_from_mem,
    // exception
    input         ws_reflush_es,
    input         ms_int,
    // block
    output        es_csr,
    output        es_tid,

    // tlb:: srch && inv
    output [              18:0] s1_vppn,
    output                      s1_va_bit12,
    output [               9:0] s1_asid,
    input                       s1_found,
    input  [$clog2(TLBNUM)-1:0] s1_index,
    input  [              19:0] s1_ppn,
    input  [               5:0] s1_ps,
    input  [               1:0] s1_plv,
    input  [               1:0] s1_mat,
    input                       s1_d,
    input                       s1_v,
    // invtlb
    output                      invtlb_valid,
    output [               4:0] invtlb_op,
    // 从WB阶段的csr传回来的数据
    // input  [63:0] to_es_tlb_bus, 
    output [38:0] to_ws_csr_bus,
    input [159:0] ws_to_es_bus,
    // 传给id阶段的重取信号
    output is_tlb
);

reg         es_valid;
wire        es_ready_go;

reg [241:0] ds_to_es_bus_r;
wire [11:0] es_alu_op;
wire        es_res_from_mem;
wire        es_gr_we;
wire        es_to_ms_gr_we;
wire        es_mem_we;
wire [ 4:0] es_dest;
wire [31:0] es_pc;
wire [31:0] es_alu_src1;
wire [31:0] es_alu_src2;
wire [31:0] es_alu_result;
wire [31:0] es_final_result;
wire [31:0] rkd_value;
wire [ 6:0] es_mul_div_op;
wire [ 7:0] es_ld_st_op;
wire        es_mul;
wire        es_div;
wire [63:0] unsigned_prod, signed_prod;
wire [31:0] es_mul_result;
wire [31:0] q_result;
wire [31:0] r_result;
wire [ 3:0] mem_write_strb;
wire [31:0] mem_write_data;
wire [ 1:0] st_vaddr;

//kernel 
wire es_csr_we;
wire es_csr_rd;
wire [31:0] es_csr_wmask;
wire [13:0] es_csr_num;
wire [16:0] es_ex_cause_bus;
wire es_ertn;
wire es_int;

wire [ 5:0] tlb_ex_bus;

// stable counter for rdcntv{l/h}.w [lxy]
reg [63:0] stable_cnt;
always @(posedge clk) begin
    if (reset)
        stable_cnt <= 64'h0;
    else
        stable_cnt <= stable_cnt + 1'b1;
end

 
wire        divisor_ready;
reg         div_valid;
wire        dividend_ready;
wire [63:0] div_result;
wire        div_done;

wire        udivisor_ready;
reg         udiv_valid;
wire        udividend_ready;
wire [63:0] udiv_result;
wire        udiv_done;

wire [31:0] es_div_result;
wire [16:0] es_ex_cause_bus_r;

wire es_rdcntid;
wire es_rdcntvl;
wire es_rdcntvh;

reg data_sram_addr_ok_r;

// exp18
wire [4:0] tlb_bus;

assign {
    tlb_bus,            //241:237
    invtlb_op,          //236:232
    es_rdcntid,         //231:231
    es_rdcntvl,         //230:230
    es_rdcntvh,         //229:229
    es_ertn,            //228:228
    // csr && kernel
    es_csr_we,          //227:227
    es_csr_rd,          //226:226
    es_csr_wmask,       //225:194
    es_csr_num,         //193:180
    es_ex_cause_bus,    //179:163
    //
    es_ld_st_op,        //162:155
    es_mul_div_op,      //154:148
    es_pc,              //147:116
    // alu
    es_alu_op,          //115:104
    es_alu_src1,        //103:72
    es_alu_src2,        //71:40
    //mem
    rkd_value,          //39:8
    es_res_from_mem,    //7:7
    es_mem_we,          //6:6
    //wb
    es_dest,            //5:1
    es_gr_we            //0:0
} = ds_to_es_bus_r;

assign unsigned_prod = es_alu_src1 * es_alu_src2;
assign signed_prod = $signed(es_alu_src1) * $signed(es_alu_src2);

assign es_mul = |es_mul_div_op[2:0];
assign es_div = |es_mul_div_op[6:3];
assign es_mul_result = {32{es_mul_div_op[0]}} & unsigned_prod[31:0]     //mul
                     | {32{es_mul_div_op[1]}} & signed_prod[63:32]       //mulh
                     | {32{es_mul_div_op[2]}} & unsigned_prod[63:32];   //mulh_u

// ! 增加错误判断：出现异常则置写使能无效
assign es_to_ms_gr_we = es_gr_we & ~(|es_ex_cause_bus_r[15:0]);

assign es_to_ms_bus = {
    // tlb_bus,            //153:149
    tlb_bus,            //148:144
    es_mem_we,          //143:143
    es_rdcntid,         //142:142
    es_ertn,            //141:141
    es_csr_we,          //140:140
    es_csr_rd,          //139:139
    es_csr_wmask,       //138:107
    es_csr_num,         //106:93
    es_ex_cause_bus_r,  //92:76

    es_ld_st_op[4:0], //75:71
    es_res_from_mem,  //70:70
    es_to_ms_gr_we,  //69:69
    es_dest,  //68:64
    es_final_result,  //63:32
    es_pc             //31:0
    };

assign es_final_result = es_mul ? es_mul_result :
                         es_div ? es_div_result : 
                         es_csr_we ? rkd_value : 
                         es_rdcntvl ? stable_cnt[31:0] :
                         es_rdcntvh ? stable_cnt[63:32] :
                         es_alu_result;


// this inst is to write reg(gr_we) and it's valid!!
assign es_to_ds_dest  = {5{es_gr_we && es_valid}} & es_dest;
assign es_to_ds_value = {32{es_gr_we && es_valid}} & es_alu_result;
assign es_value_from_mem = es_valid && es_res_from_mem;

assign es_ready_go    = ((es_res_from_mem || es_mem_we) && ~ws_reflush_es) ? ((data_sram_req & data_sram_addr_ok) || data_sram_addr_ok_r)
                        : ~(|es_mul_div_op[6:3] && ~(udiv_done || div_done));//1'b1; // 是div指令，且没有done
assign es_allowin     = !es_valid || es_ready_go && ms_allowin;
assign es_to_ms_valid =  es_valid && es_ready_go && !ws_reflush_es;

always @(posedge clk) begin
    if (reset) begin
        es_valid <= 1'b0;
    end
    else if(ws_reflush_es) begin
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

always @(posedge clk)
begin
    if(reset) begin
        div_valid <= 1'b0;
    end
    else if(div_valid & divisor_ready & dividend_ready) begin
        div_valid <= 1'b0;
    end
    else if(ds_to_es_valid && es_allowin) begin
        div_valid <= | ds_to_es_bus[152:151];
    end
end

always @(posedge clk)
begin
    if(reset) begin
        udiv_valid <= 1'b0;
    end
    else if(udiv_valid & udivisor_ready & udividend_ready) begin
        udiv_valid <= 1'b0;
    end
    else if(ds_to_es_valid && es_allowin) begin
        udiv_valid <= | ds_to_es_bus[154:153];
    end
end

assign q_result = {32{es_mul_div_op[3]}} & div_result[63:32] | {32{es_mul_div_op[5]}} & udiv_result[63:32];
assign r_result = {32{es_mul_div_op[4]}} & div_result[31:0] | {32{es_mul_div_op[6]}} & udiv_result[31:0];

assign es_div_result = q_result | r_result;

alu u_alu(
    .alu_op     (es_alu_op    ),
    .alu_src1   (es_alu_src1  ),
    .alu_src2   (es_alu_src2  ),
    .alu_result (es_alu_result)
    );

signed_divider my_signed_divider(
    .aclk                   (clk),
    // S_AXIS_DIVISOR: rk
    .s_axis_divisor_tdata   (es_alu_src2),
    .s_axis_divisor_tready  (divisor_ready),
    .s_axis_divisor_tvalid  (div_valid),
    // S_AXIS_DIVIDEND: rj
    .s_axis_dividend_tdata  (es_alu_src1),
    .s_axis_dividend_tready (dividend_ready),
    .s_axis_dividend_tvalid (div_valid),
    // M_AXIS_DOUT
    .m_axis_dout_tdata      (div_result),
    .m_axis_dout_tvalid     (div_done)
);

unsigned_divider my_unsigned_divider(
    .aclk                   (clk),
    // S_AXIS_DIVISOR: rk
    .s_axis_divisor_tdata   (es_alu_src2),
    .s_axis_divisor_tready  (udivisor_ready),
    .s_axis_divisor_tvalid  (udiv_valid),
    // S_AXIS_DIVIDEND: rj
    .s_axis_dividend_tdata  (es_alu_src1),
    .s_axis_dividend_tready (udividend_ready),
    .s_axis_dividend_tvalid (udiv_valid),
    // M_AXIS_DOUT
    .m_axis_dout_tdata      (udiv_result),
    .m_axis_dout_tvalid     (udiv_done) 
);

// add st.b, st.h & st.w
assign st_vaddr = es_alu_result[1:0];
// es_ld_st_op[0] -> inst_ld_b;
// es_ld_st_op[1] -> inst_ld_bu
// es_ld_st_op[2] -> inst_ld_h;
// es_ld_st_op[3] -> inst_ld_hu
// es_ld_st_op[4] -> inst_ld_w;
// es_ld_st_op[5] -> inst_st_b;
// es_ld_st_op[6] -> inst_st_h;
// es_ld_st_op[7] -> inst_st_w;
assign mem_write_strb = (es_ld_st_op[5] && st_vaddr == 2'b00) ? 4'b0001 :
                        (es_ld_st_op[5] && st_vaddr == 2'b01) ? 4'b0010 :
                        (es_ld_st_op[5] && st_vaddr == 2'b10) ? 4'b0100 :
                        (es_ld_st_op[5] && st_vaddr == 2'b11) ? 4'b1000 :
                        (es_ld_st_op[6] && st_vaddr == 2'b00) ? 4'b0011 :
                        (es_ld_st_op[6] && st_vaddr == 2'b10) ? 4'b1100 :
                                                                4'b1111 ;
assign mem_write_data = es_ld_st_op[5] ? {4{rkd_value[ 7:0]}} :
                        es_ld_st_op[6] ? {2{rkd_value[15:0]}} :
                                            rkd_value[31:0];

//hk:exp14
always @(posedge clk) begin
    if(reset) 
        data_sram_addr_ok_r <= 1'b0;
    else if(data_sram_addr_ok && data_sram_req && !ms_allowin) 
        data_sram_addr_ok_r <= 1'b1;    
    else if(ms_allowin) 
        data_sram_addr_ok_r <= 1'b0;
end

assign data_sram_req   = (es_res_from_mem || es_mem_we) && es_valid && ~ws_reflush_es && !data_sram_addr_ok_r && ms_allowin && !ms_int /*&& !(|tlb_ex_bus)*/;  //取回来下一拍的要被cancel
assign data_sram_wr    = |data_sram_wstrb && ~|tlb_ex_bus;
assign data_sram_size  = (es_ld_st_op[4] || es_ld_st_op[7]) ? 2'h2
                        :(es_ld_st_op[2] || es_ld_st_op[3] || es_ld_st_op[6]) ? 2'h1
                        :2'h0;
// assign data_sram_addr  = es_alu_result;
assign data_sram_wstrb = (es_mem_we && es_valid && !ms_int && !es_int) ? mem_write_strb : 4'h0;
assign data_sram_wdata = mem_write_data;

// lzh:: exp18: 处理TLBSRCH, INVTLB指令
/*
 * 在exp18中, 正常指令不会使用到TLB, 只有几个和TLB维护相关的指令才会用到
    ! inst_tlbsrch, inst_tlbrd, inst_tlbwr, inst_tlbfill, inst_invtlb bus顺序, 4-0
 * 在exe阶段有效的只有srch和invtlb, 也就是4和0, 其余的要传下去
 * SRCH需要用到CSR.ASID, CSR.TLBEHI, 需要从WB阶段传回来
 * 然后传入tlb, 返回index和found, 如果found为1-->命中(此时不能有其他异常在该阶段)
    * 将tlbsrch_hit拉高, 传入csr_tlbidx_wvalue( index 和 ne = 0)
    * 没有命中项则拉高ne位
    ? 综上所述: srch为 input(csr_asid_rvalue, csr_tlbehi_rvalue)--> output(tlbsrch_hit, csr_tlbidx_wvalue)
 * INVTLB则是从上一级传来的数据操作, 只需要传入vppn和asid, 还有op即可
 ! 由于已经更改csr阻塞逻辑, 现在只要是csr指令进入后三流水, 就hi发生阻塞, 所以在csr工作时, 不可能发生任何的csr冲突
 */

// assign s1_vppn = (es_res_from_mem || es_mem_we) ? ls_vppn:tlb_bus[0]?es_alu_src2[31:13]:csr_tlbehi_rvalue[31:13];
// assign s1_va_bit12 = (es_res_from_mem || es_mem_we) ? ls_va_bit12:1'b0;
// assign s1_asid = (es_res_from_mem || es_mem_we) ? ls_asid:tlb_bus[0]?es_alu_src1[9:0]:csr_asid_rvalue[9:0];
wire [31:0] csr_asid_rvalue;
wire [31:0] csr_tlbehi_rvalue;
wire tlbsrch_hit;
wire [31:0] csr_tlbidx_wvalue;
wire srch_valid;
wire [31:0] csr_crmd_rvalue;
wire [31:0] csr_dmw0_rvalue;
wire [31:0] csr_dmw1_rvalue;
assign {csr_tlbehi_rvalue, csr_crmd_rvalue, csr_dmw0_rvalue, csr_dmw1_rvalue, csr_asid_rvalue} = ws_to_es_bus;
assign srch_valid = es_valid & tlb_bus[4];
assign tlbsrch_hit = srch_valid & s1_found & ~|es_ex_cause_bus_r;
assign csr_tlbidx_wvalue = {~s1_found, 1'b0, s1_ps, 20'b0, s1_index };

// assign {csr_asid_rvalue, csr_tlbehi_rvalue} = to_es_tlb_bus;
assign to_ws_csr_bus = {srch_valid, tlbsrch_hit, tlb_bus, csr_tlbidx_wvalue};

// exp19加入真实查找tlb信号:
wire [18:0] mem_vppn;
wire mem_va_bit12;
wire [9:0] mem_asid;

assign s1_vppn = ({19{(es_res_from_mem||es_mem_we)}} & mem_vppn )
                | ({19{tlb_bus[0]}} & es_alu_src2[31:13]) 
                | ({19{tlb_bus[4]}} & csr_tlbehi_rvalue[31:13]);
assign s1_asid = ({9{(es_res_from_mem||es_mem_we)}} & mem_asid )
                | ({9{tlb_bus[0]}} & es_alu_src1[9:0]) 
                | ({9{tlb_bus[4]}} & csr_asid_rvalue[9:0]);
assign s1_va_bit12 = (es_res_from_mem||es_mem_we) ? mem_va_bit12:1'b0;

assign invtlb_valid = es_valid & tlb_bus[0];
assign is_tlb = |tlb_bus;  // 写特定寄存器也会造成重取
    //(es_csr_we & (es_csr_num== 14'h0 || es_csr_num == 14'h180 || es_csr_num==14'h181 || es_csr_num==14'h18));
// assign invtlb_op = 已在之前的assign中添加

// exp19 添加访存op
wire [ 2: 0] inst_op;
assign inst_op = {es_res_from_mem,es_mem_we,1'b0};
vaddr_transfer data_transfer(
    .va        (es_alu_result),
    .inst_op   (inst_op),
    .pa        (data_sram_addr),
    .tlb_ex_bus(tlb_ex_bus),

    .s_vppn    (mem_vppn), // 输出三个tlb中值, 需要进行选择, 是指令值接入tlb还是地址值
    .s_va_bit12(mem_va_bit12),
    .s_asid    (mem_asid),
    .s_found   (s1_found),
    .s_index   (s1_index),
    .s_ppn     (s1_ppn),
    .s_ps      (s1_ps),
    .s_plv     (s1_plv),
    .s_mat     (s1_mat),
    .s_d       (s1_d),
    .s_v       (s1_v),

    .csr_asid  (csr_asid_rvalue),
    .csr_crmd  (csr_crmd_rvalue),

    .dmw_hit   (dmw_hit),
    .csr_dmw0  (csr_dmw0_rvalue),
    .csr_dmw1  (csr_dmw1_rvalue)
    
);

// generate ALE exception signal
// here st_vaddr acts both as st_vaddr and ld_vaddr, 
// because we must fully generate ALE exception signal at this stage
// ! 还需要重新对当前的tlb_ex_bus判断
assign es_ex_cause_bus_r[6'h3/*ALE*/] = ((st_vaddr[0] != 1'b0) && 
                                         (es_ld_st_op[2] || es_ld_st_op[3] || es_ld_st_op[6])) ||
                                        ((st_vaddr[1:0] != 2'b00) &&
                                         (es_ld_st_op[4] || es_ld_st_op[7]));
assign es_ex_cause_bus_r[5:4] = es_ex_cause_bus[5:4];
// ! 其实此时应该直接等于, 但由于总线未作例外屏蔽, 只能出此下策
assign es_ex_cause_bus_r[6'h6/*PME    */] = es_ex_cause_bus[6'h6/*PME    */] || (es_valid & tlb_ex_bus[5]);
assign es_ex_cause_bus_r[6'h7/*PPI    */] = es_ex_cause_bus[6'h7/*PPI    */] || (es_valid & tlb_ex_bus[4]);
assign es_ex_cause_bus_r[6'h8/*PIS    */] = es_ex_cause_bus[6'h8/*PIS    */] || (es_valid & tlb_ex_bus[3]);
assign es_ex_cause_bus_r[6'h9/*PME    */] = es_ex_cause_bus[6'h9/*PME    */] || (es_valid & tlb_ex_bus[2]);
assign es_ex_cause_bus_r[6'ha/*PIF    */] = es_ex_cause_bus[6'ha/*PIF    */] || (es_valid & tlb_ex_bus[1]);
assign es_ex_cause_bus_r[6'hb/*TLBR   */] = es_ex_cause_bus[6'hb/*TLBR   */] || (es_valid & tlb_ex_bus[0]);
assign es_ex_cause_bus_r[6'hd/*ADEM   */] = (es_res_from_mem||es_mem_we) & es_alu_result[31] & (csr_crmd_rvalue[1:0]!=0) & ~dmw_hit;
assign es_ex_cause_bus_r[16:14] = es_ex_cause_bus[16:14];
assign es_ex_cause_bus_r[12] = es_ex_cause_bus[12];
assign es_ex_cause_bus_r[ 2:0] = es_ex_cause_bus[ 2:0];

assign es_int = es_ex_cause_bus_r[6'h3];

assign es_csr = (es_csr_we || es_csr_rd) & es_valid;
assign es_tid = es_rdcntid & es_valid;

endmodule