module vaddr_transfer(
    input wire  [31:0] va,       // 传入的虚地址
    input wire  [ 2:0] inst_op,  // 三类输入{load.store,inst}
    output wire [31:0] pa,       // 输出的实地址
    output wire [ 5:0] tlb_ex_bus,//{PME,PPI,PIS,PIL,PIF,TLBR}, 相关的异常
    // tlb:: 和s0/1连接
    output wire [18:0] s_vppn,
    output wire        s_va_bit12,
    output wire [ 9:0] s_asid,
    input wire         s_found,
    input wire  [ 3:0] s_index,
    input wire  [19:0] s_ppn,
    input wire  [ 5:0] s_ps,
    input wire  [ 1:0] s_plv,
    input wire  [ 1:0] s_mat,
    input wire         s_d,
    input wire         s_v,
    // crmd:: 读入csr中信息做判断
    input wire  [31:0] csr_asid,
    input wire  [31:0] csr_crmd,
    // dmw:: 从dmw中得到翻译信息
    output wire dmw_hit,
    input wire  [31:0] csr_dmw0,
    input wire  [31:0] csr_dmw1
);
// ! 两种模式
wire direct_mode;
wire mapping_mode;
assign direct_mode = csr_crmd[3] & ~csr_crmd[4]; // da = 1 && pg = 0
assign mapping_mode = ~csr_crmd[3] & csr_crmd[4];

//direct
wire dmw_hit0;
wire dmw_hit1;
wire [31:0] dmw_pa0;
wire [31:0] dmw_pa1;
wire [31:0] tlb_pa;

// * 直接映射地址翻译模式
    assign dmw_hit  = dmw_hit0 | dmw_hit1;
    assign dmw_hit0 = csr_dmw0[csr_crmd[1:0]] && (csr_dmw0[31:29]==va[31:29]);
    assign dmw_hit1 = csr_dmw1[csr_crmd[1:0]] && (csr_dmw1[31:29]==va[31:29]);
    assign dmw_pa0  = {csr_dmw0[27:25],va[28:0]};
    assign dmw_pa1  = {csr_dmw1[27:25],va[28:0]};
// * 页表的虚实转换
    // ! output wire
    assign s_vppn =  va[31:13];
    assign s_va_bit12 = va[12];
    assign s_asid =  csr_asid[9:0];
    // ! input wire--翻译
    assign tlb_pa = (s_ps==6'd12)? {s_ppn[19:0],va[11:0]} : {s_ppn[19:10],va[21:0]};
    // ! 异常:{PME,PPE,PIS,PIL,PIF,TLBR}
    assign tlb_ex_bus = {6{!direct_mode}} & // 如果是直接模式, 就不会由tlb报异常
            {6{!dmw_hit}} &  // 如果dmw命中, 也不会考虑tlb异常
            {6{|inst_op}} & {// 如果inst_op有效
            inst_op[1]    & ~s_d, // 页修改异常:: PME
            csr_crmd[1:0] > s_plv,// 页权限异常:: PPI
            inst_op[1]    & ~s_v, // store页无效例外:: PIS
            inst_op[2]    & ~s_v, // 取指页无效:: PIF
            inst_op[0]    & ~s_v, // load页无效:: PIL
            ~s_found};// 页重填例外

    // input wire  [ 3:0] s_index, 两个未用到的信号端口
    // input wire  [ 1:0] s_mat,
// ! 获得实地址
/*
 * 第一步, 首先看是否是direct, 若是则直接返回va地址作为pa
 * 查看是否由dwm翻译命中, 否则选择tlb_pa
 */
assign pa = direct_mode ? va:
        (dmw_hit0 ? dmw_pa0 :
        (dmw_hit1 ? dmw_pa1 : tlb_pa));


endmodule