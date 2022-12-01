`timescale 1ns / 1ps

/*
 ! 对于TLB项的分析放在了逻辑较少的读端口, 见xxx行
 * 
 */

module tlb
#(
    parameter TLBNUM = 16
)
(
    input wire clk,
    // * 双端口设计, 分别为指令和访存设计, 支持流水线高速运转.
    // ! 指令端口
    input wire  [              18:0] s0_vppn,        // * 来自访存虚地址[31:13]
    input wire                       s0_va_bit12,    // * 来自访存虚地址的第12位
    input wire  [               9:0] s0_asid,        // * 来自CSR.ASID的ASID域
    output wire                      s0_found,       // ! 判定是否产生异常
    output wire [$clog2(TLBNUM)-1:0] s0_index,       // * 索引位, 标识, 命中第几项, 其信息填入到CSR.TLBIDX中
    output wire [              19:0] s0_ppn,         // ! 和ps一起用于产生最后的实地址
    output wire [               5:0] s0_ps,
    output wire [               1:0] s0_plv,
    output wire [               1:0] s0_mat,         
    output wire                      s0_d,
    output wire                      s0_v,
    // ! 访存端口
    input wire  [              18:0] s1_vppn,
    input wire                       s1_va_bit12,
    input wire  [               9:0] s1_asid,
    output wire                      s1_found,
    output wire [$clog2(TLBNUM)-1:0] s1_index,
    output wire [              19:0] s1_ppn,
    output wire [               5:0] s1_ps,
    output wire [               1:0] s1_plv,
    output wire [               1:0] s1_mat,
    output wire                      s1_d,
    output wire                      s1_v,
    // 清楚无效的TLB表项指令 支持
    input wire                       invtlb_valid,
    input wire  [               4:0] invtlb_op,
    // * 支持TLBWR和TLBFILL指令
    input wire                       we, 
    input wire  [$clog2(TLBNUM)-1:0] w_index,
    input wire                       w_e,
    input wire  [               5:0] w_ps,
    input wire  [              18:0] w_vppn,
    input wire  [               9:0] w_asid,
    input wire                       w_g,
    input wire  [              19:0] w_ppn0,
    input wire  [               1:0] w_plv0,
    input wire  [               1:0] w_mat0,
    input wire                       w_d0,
    input wire                       w_v0,
    input wire  [              19:0] w_ppn1,
    input wire  [               1:0] w_plv1,
    input wire  [               1:0] w_mat1,
    input wire                       w_d1,
    input wire                       w_v1,
    // 支持TLB读指令
    input wire  [$clog2(TLBNUM)-1:0] r_index,
    output wire                      r_e,
    output wire [              18:0] r_vppn,
    output wire [               5:0] r_ps,
    output wire [               9:0] r_asid,
    output wire                      r_g,
    output wire [              19:0] r_ppn0,
    output wire [               1:0] r_plv0,
    output wire [               1:0] r_mat0,
    output wire                      r_d0,
    output wire                      r_v0,
    output wire [              19:0] r_ppn1,     
    output wire [               1:0] r_plv1,
    output wire [               1:0] r_mat1,
    output wire                      r_d1,
    output wire                      r_v1
);
// var declaration
    reg [TLBNUM-1:0] tlb_e;
    reg [TLBNUM-1:0] tlb_ps4MB; //pagesize 1:4MB, 0:4KB
    reg [      18:0] tlb_vppn [TLBNUM-1:0];
    reg [       9:0] tlb_asid [TLBNUM-1:0];
    reg              tlb_g    [TLBNUM-1:0];
    reg [      19:0] tlb_ppn0 [TLBNUM-1:0];
    reg [       1:0] tlb_plv0 [TLBNUM-1:0];
    reg [       1:0] tlb_mat0 [TLBNUM-1:0];
    reg              tlb_d0   [TLBNUM-1:0];
    reg              tlb_v0   [TLBNUM-1:0];
    reg [      19:0] tlb_ppn1 [TLBNUM-1:0];
    reg [       1:0] tlb_plv1 [TLBNUM-1:0];
    reg [       1:0] tlb_mat1 [TLBNUM-1:0];
    reg              tlb_d1   [TLBNUM-1:0];
    reg              tlb_v1   [TLBNUM-1:0];
    
// * 记录两个TLB谁会命中(0 for inst, 1 for mem)
    wire [TLBNUM - 1:0] match0;
    wire [TLBNUM - 1:0] match1; 
// ! 用作选择页表项中的两项, 1表示pte1, 0 表示pte0(其实就是地址)
    wire pick_num0; 
    wire pick_num1;
// useless
    wire [2:0] attr [TLBNUM-1:0]; // 每个表项的三种性质 attribute
    wire [TLBNUM-1:0] inv_match;  // inv_op 时, 组合地得到匹配项, 随后根据匹配项修改exist项
    genvar tlb_index;

// !! 奇偶项选择
    /*
     ! 这一步逻辑需要仔细观察
     ? 仔细思考4KB和4MB下, 对于[31:0]的虚地址, 该在哪里得到0/1
     * 对于4KB, ps4MB = 0, 则va[11:0]为页偏移, va[12]为标识奇偶页号, va[31:13]为虚拟页号, 也就是传入的vppn
     * 对于4MB, ps4MB = 1, 则va[21:0]为页偏移, va[22]为标识奇偶页号, va[31:23]为虚拟页号, 也就是传入的vppn[18:10]
     ! 所以4KB, 奇偶号为va[12]--> va_bit12; 4MB, 奇偶号为va[22]-->vppn[9]
     */
    assign pick_num0 = tlb_ps4MB[s0_index] ? s0_vppn[9] : s0_va_bit12;
    assign pick_num1 = tlb_ps4MB[s1_index] ? s1_vppn[9] : s1_va_bit12;
    // 得到实际的输出
    assign s0_ppn   = pick_num0 ? tlb_ppn1[s0_index] : tlb_ppn0[s0_index];
    assign s0_ps    = tlb_ps4MB[s0_index] ? 6'd22 : 6'd12;
    assign s0_plv   = pick_num0 ? tlb_plv1[s0_index] : tlb_plv0[s0_index];
    assign s0_mat   = pick_num0 ? tlb_mat1[s0_index] : tlb_mat0[s0_index];
    assign s0_d     = pick_num0 ? tlb_d1[s0_index] : tlb_d0[s0_index];
    assign s0_v     = pick_num0 ? tlb_v1[s0_index] : tlb_v0[s0_index];
    
    assign s1_ppn   = pick_num1 ? tlb_ppn1[s1_index] : tlb_ppn0[s1_index];
    assign s1_ps    = tlb_ps4MB[s1_index] ? 6'd22 : 6'd12;
    assign s1_plv   = pick_num1 ? tlb_plv1[s1_index] : tlb_plv0[s1_index];
    assign s1_mat   = pick_num1 ? tlb_mat1[s1_index] : tlb_mat0[s1_index];
    assign s1_d     = pick_num1 ? tlb_d1[s1_index] : tlb_d0[s1_index];
    assign s1_v     = pick_num1 ? tlb_v1[s1_index] : tlb_v0[s1_index];  



// ! TLB-match区
        generate // ! 用来对比TLB表项, 生成两个match regs
        for(tlb_index = 0; tlb_index < TLBNUM; tlb_index=tlb_index+1)
        begin: __TLB_compare
                assign match0[tlb_index] = // ! 虚拟地址对上 + 页数对上 + asid对上 + exist
                (s0_vppn[18:10] == tlb_vppn[tlb_index][18:10]) && tlb_e[tlb_index]
                && (tlb_ps4MB[tlb_index] || s0_vppn[9:0]==tlb_vppn[tlb_index][9:0])
                && (s0_asid == tlb_asid[tlb_index] || tlb_g[tlb_index]);

                assign match1[tlb_index] = 
                (s1_vppn[18:10] == tlb_vppn[tlb_index][18:10]) && tlb_e[tlb_index]
                && (tlb_ps4MB[tlb_index] || s1_vppn[9:0]==tlb_vppn[tlb_index][ 9: 0])
                && (s1_asid == tlb_asid[tlb_index] || tlb_g[tlb_index]);
        end
        endgenerate

    // 是否found
    assign s0_found = |match0;
    assign s1_found = |match1;
    // ! 采用书上介绍的 "经典" 选择逻辑
    assign s0_index = ({4{match0[0]}} & 4'd0)   | ({4{match0[1]}} & 4'd1)
                    | ({4{match0[2]}} & 4'd2)   | ({4{match0[3]}} & 4'd3)
                    | ({4{match0[4]}} & 4'd4)   | ({4{match0[5]}} & 4'd5)
                    | ({4{match0[6]}} & 4'd6)   | ({4{match0[7]}} & 4'd7)
                    | ({4{match0[8]}} & 4'd8)   | ({4{match0[9]}} & 4'd9)
                    | ({4{match0[10]}} & 4'd10) | ({4{match0[11]}} & 4'd11)
                    | ({4{match0[12]}} & 4'd12) | ({4{match0[13]}} & 4'd13)
                    | ({4{match0[14]}} & 4'd14) | ({4{match0[15]}} & 4'd15);
    assign s1_index = ({4{match1[0]}} & 4'd0)   | ({4{match1[1]}} & 4'd1)
                    | ({4{match1[2]}} & 4'd2)   | ({4{match1[3]}} & 4'd3)
                    | ({4{match1[4]}} & 4'd4)   | ({4{match1[5]}} & 4'd5)
                    | ({4{match1[6]}} & 4'd6)   | ({4{match1[7]}} & 4'd7)
                    | ({4{match1[8]}} & 4'd8)   | ({4{match1[9]}} & 4'd9)
                    | ({4{match1[10]}} & 4'd10) | ({4{match1[11]}} & 4'd11)
                    | ({4{match1[12]}} & 4'd12) | ({4{match1[13]}} & 4'd13)
                    | ({4{match1[14]}} & 4'd14) | ({4{match1[15]}} & 4'd15);
    
    

// ! invtlab
/*
 ? 对op的解释:
 * 0x0:: 清除所有表项
 * 0x1:: 清除所有页表项, 和0x0一致
 * 0x2:: 清除所有G=1的页表项
 * 0x3:: 清除所有G=0的页表项
 * 0x4:: 清除所有G=0, 且ASID等于寄存器指定ASID的页表项
 * 0x5:: 清除G=0, ASID等于寄存器指定ASID的页表项, 且VA一致的页表项
 * 0x6:: 清除G=1, ASID等于寄存器指定ASID的页表项, 且VA一致的页表项
 ! 综合考虑, 共有3种组合项
 */
    generate // * 首先得到匹配的表项
        for(tlb_index = 0; tlb_index < TLBNUM; tlb_index=tlb_index+1)
        begin: __flush_TLB_prepare
            // ! 三项分别代表, G==1; asid对应; va一致(也就是虚拟页表对应, 要么)
            assign attr[tlb_index][0] = tlb_g[tlb_index];
            assign attr[tlb_index][1] = s1_asid == tlb_asid[tlb_index];
            assign attr[tlb_index][2] = (s1_vppn[18:10]==tlb_vppn[tlb_index][18:10]) // 高位必须一一对应
               && (tlb_ps4MB[tlb_index] || s1_vppn[9:0]==tlb_vppn[tlb_index][ 9: 0]); // 低位则当4KB时, 才需要一一对应

            assign inv_match[tlb_index] = ((invtlb_op==0||invtlb_op==1) & 1'b1)  // all
                                         ||((invtlb_op==2) & (attr[tlb_index][0]))  // G = 1
                                         ||((invtlb_op==3) & (!attr[tlb_index][0]))  // G = 0
                                         ||((invtlb_op==4) & (!attr[tlb_index][0]) & (attr[tlb_index][1])) // G=0, ASID一致
                                         ||((invtlb_op==5) & (!attr[tlb_index][0]) & attr[tlb_index][1] & attr[tlb_index][2])
                                         ||((invtlb_op==6) & (attr[tlb_index][0] | attr[tlb_index][1]) & attr[tlb_index][2]);
          end
    endgenerate              

//     always @(posedge clk ) begin // ! 用来产生写入信息
//         generate 
//             for(tlb_index = 0; tlb_index < TLBNUM; tlb_index = tlb_index+1)
//             begin: __inv_TLB
//                 if(inv_match[tlb_index] & invtlb_valid)
//                     tlb_e[tlb_index] <= 1'b0;
//             end 
//         endgenerate
//     end

    always @(posedge clk ) begin
        if(inv_match[0] & invtlb_valid)
                tlb_e[0] <= 1'b0;
        if(inv_match[1] & invtlb_valid)
                tlb_e[1] <= 1'b0;
        if(inv_match[2] & invtlb_valid)
                tlb_e[2] <= 1'b0;
        if(inv_match[3] & invtlb_valid)
                tlb_e[3] <= 1'b0;
        if(inv_match[4] & invtlb_valid)
                tlb_e[4] <= 1'b0;
        if(inv_match[5] & invtlb_valid)
                tlb_e[5] <= 1'b0;
        if(inv_match[6] & invtlb_valid)
                tlb_e[6] <= 1'b0;
        if(inv_match[7] & invtlb_valid)
                tlb_e[7] <= 1'b0;
        if(inv_match[8] & invtlb_valid)
                tlb_e[8] <= 1'b0;
        if(inv_match[9] & invtlb_valid)
                tlb_e[9] <= 1'b0;
        if(inv_match[10] & invtlb_valid)
                tlb_e[10] <= 1'b0;
        if(inv_match[11] & invtlb_valid)
                tlb_e[11] <= 1'b0;
        if(inv_match[12] & invtlb_valid)
                tlb_e[12] <= 1'b0;
        if(inv_match[13] & invtlb_valid)
                tlb_e[13] <= 1'b0;
        if(inv_match[14] & invtlb_valid)
                tlb_e[14] <= 1'b0;
        if(inv_match[15] & invtlb_valid)
                tlb_e[15] <= 1'b0;
        if(we)
                tlb_e[w_index] <= w_e;
    end
    

// ! 写端口
    always @(posedge clk) begin
        if (we) begin :__TLB_Write

        //     tlb_e[w_index] <= w_e;
            
            tlb_ps4MB[w_index]  <= (w_ps==6'd22);
            tlb_vppn[w_index]   <= w_vppn;
            tlb_asid[w_index]   <= w_asid;
            tlb_g[w_index]      <= w_g;
            
            tlb_ppn0[w_index]   <= w_ppn0;
            tlb_plv0[w_index]   <= w_plv0;
            tlb_mat0[w_index]   <= w_mat0;
            tlb_d0[w_index]     <= w_d0;
            tlb_v0[w_index]     <= w_v0;
            
            tlb_ppn1[w_index]   <= w_ppn1;
            tlb_plv1[w_index]   <= w_plv1;
            tlb_mat1[w_index]   <= w_mat1;
            tlb_d1[w_index]     <= w_d1;
            tlb_v1[w_index]     <= w_v1;
        end
    end

// ! 读端口
    // * 存在位, 可以解释称enable/empty/exist, 但考虑到1为非空, 可以参与到查找匹配, 所以应该是Exist
    assign r_e = tlb_e[r_index];
    // * 地址空间标志位, address space id, 10bits, 用于区分不同进程, 避免switch后清空整个TLB带来的性能损失. 在查找时比对
    assign r_asid = tlb_asid[r_index];
    // * 全局标志位, Global, 该位为1时, 查找不进行asid比对, 表明是共享的空间
    assign r_g = tlb_g[r_index];
    // * 页大小, PageSize, 6bits, 仅在MTLB中出现. 精简版只支持4KB和4MB
    assign r_ps = tlb_ps4MB[r_index] ? 6'd22 : 6'd12;
    // ! 虚双页号, VALEN-13 bits, 由于一项放两页, 所以末尾对齐, 如32位va, 只需要19-1位, 余下input(va_bits12来判断奇偶页)
    assign r_vppn = tlb_vppn[r_index];
    
    // * 有效位, Valid 1表示有效且被访问过的. 
    assign r_v0 = tlb_v0[r_index];
    assign r_v1 = tlb_v1[r_index];
    // * 脏位, Dirty, 1表示该表项对应页内数据已被改写过
    assign r_d0 = tlb_d0[r_index];
    assign r_d1 = tlb_d1[r_index];
    // * 存储访问类型, Mem Access Type, 2bits, 控制该页地址空间上访存类型
    assign r_mat0 = tlb_mat0[r_index];
    assign r_mat1 = tlb_mat1[r_index];
    // * 特权等级, Privilege LeVel, 2bits, 可以被任何不低于PLV中等级态访问
    assign r_plv0 = tlb_plv0[r_index];
    assign r_plv1 = tlb_plv1[r_index];
    // ! 物理页号, PhysicalPageNum, PALEN-12 bits, 根据PS判定位数有效
    assign r_ppn0 = tlb_ppn0[r_index];
    assign r_ppn1 = tlb_ppn1[r_index];
    
endmodule