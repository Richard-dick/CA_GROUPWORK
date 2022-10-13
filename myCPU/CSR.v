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

// CSR_SEL declaration
    `define CSR_CRMD_PLV      1 :0  
    `define CSR_CRMD_IE       2
    `define CSR_CRMD_DA       3
    `define CSR_CRMD_PG       4 
    `define CSR_PRMD_PPLV     1 :0
    `define CSR_PRMD_PIE      2
    `define CSR_ECFG_LIE      12:0
    `define CSR_ESTAT_IS10    1 :0
    `define CSR_TICLR_CLR     0
    `define CSR_ERA_PC        31:0
    `define CSR_EENTRY_VA     31:6
    `define CSR_SAVE_DATA     31:0
    `define CSR_TID_TID       31:0
    `define CSR_TCFG_EN       0
    `define CSR_TCFG_PERIOD   1
    `define CSR_TCFG_INITV    31:2
    `define CSR_TCFG_INITVAL  31:2


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

module csr(
    input          clk,
    input          reset,
// read port
    input  [13: 0] csr_num,
    output [31: 0] csr_rvalue,
// write port
    input          csr_we,
    input  [31: 0] csr_wmask,
    input  [31: 0] csr_wvalue,

// exceptino trigger
    input          ws_ex, 
    input  [5 : 0] ws_ecode, 
    input  [8 : 0] ws_esubcode,
    input  [31: 0] ws_pc,
    input          ertn,  //ertn

    output         has_int, 
    output [31: 0] ex_entry, 
    output [31: 0] era_entry,
    
    input  [7 : 0] hw_int_in,
    input          ipi_int_in
);


//CRMD
    reg  [ 1: 0] csr_crmd_plv;
    reg          csr_crmd_ie;
    reg          csr_crmd_da;
    reg          csr_crmd_pg;
    wire  [31:0] csr_crmd_rvalue;

//PRMD
    reg  [ 1: 0] csr_prmd_pplv;
    reg          csr_prmd_pie;
    wire [31: 0] csr_prmd_rvalue;
 
//ECFG
reg  [12: 0] csr_ecfg_lie;
wire [31: 0] csr_ecfg_rvalue;

//ESTAT
reg  [12: 0] csr_estat_is;
reg  [21:16] csr_estat_ecode;
reg  [30:22] csr_estat_esubcode;
wire [31: 0] csr_estat_rvalue;

//ERA
reg  [31: 0] csr_era_pc;
wire [31: 0] csr_era_rvalue;

//BADV
wire         es_ex_addr_err;
reg  [31: 0] csr_badv_vaddr;
wire [31: 0] csr_badv_rvalue;

//EENTRY
reg  [31: 6] csr_eentry_va;
wire [31: 0] csr_eentry_rvalue;

//SAVE0~3
reg  [31: 0] csr_save0_data;
reg  [31: 0] csr_save1_data;
reg  [31: 0] csr_save2_data;
reg  [31: 0] csr_save3_data;
wire [31: 0] csr_save0_rvalue;
wire [31: 0] csr_save1_rvalue;
wire [31: 0] csr_save2_rvalue;
wire [31: 0] csr_save3_rvalue;

//TID
reg  [31: 0] csr_tid_tid;
wire [31: 0] csr_tid_rvalue;

//TCFG
    reg          csr_tcfg_en;
    reg          csr_tcfg_periodic;
    reg  [31: 2] csr_tcfg_initval;
    wire [31: 0] csr_tcfg_rvalue;

//TVAL
wire [31: 0] tcfg_next_value;
reg  [31: 0] timer_cnt;
wire [31: 0] csr_tval_timeval;
wire [31: 0] csr_tval_rvalue;

//TICLR
wire         csr_ticlr_clr;
wire [31: 0] csr_ticlr_rvalue;



// CRMD PLV&&IE
always @(posedge clk) begin
    if (reset) begin
        csr_crmd_plv <= 2'b0;
        csr_crmd_ie <= 1'b0;
        csr_crmd_da <= 1'b1;
        csr_crmd_pg <= 1'b0;
    end
    else if (ws_ex) begin
        csr_crmd_plv <= 2'b0;
        csr_crmd_ie <= 1'b0;
    end
    else if (ertn) begin
        csr_crmd_plv <= csr_prmd_pplv;
        csr_crmd_ie <= csr_prmd_pie;
    end
    else if (csr_we && csr_num==`CSR_CRMD) begin
        csr_crmd_plv <= csr_wmask[`CSR_CRMD_PLV]&csr_wvalue[`CSR_CRMD_PLV]
                    | ~csr_wmask[`CSR_CRMD_PLV]&csr_crmd_plv;
        csr_crmd_ie <= csr_wmask[`CSR_PRMD_PIE] & csr_wvalue[`CSR_PRMD_PIE]
                    | ~csr_wmask[`CSR_PRMD_PIE] & csr_crmd_ie;
    end
end

//PRMD PPLV&&IE
always @(posedge clk) begin
    if(ws_ex) begin
        csr_prmd_pplv <= csr_crmd_plv;
        csr_prmd_pie  <= csr_crmd_ie;
    end
    else if(csr_we && csr_num == `CSR_PRMD) begin
        csr_prmd_pplv <= csr_wmask[`CSR_PRMD_PPLV]&csr_wvalue[`CSR_PRMD_PPLV]
                      | ~csr_wmask[`CSR_PRMD_PPLV]&csr_prmd_pplv;
        csr_prmd_pie  <= csr_wmask[`CSR_PRMD_PIE]&csr_wvalue[`CSR_PRMD_PIE]
                      | ~csr_wmask[`CSR_PRMD_PIE]&csr_prmd_pie;
    end
end

// ECFG LIE
always @(posedge clk) begin
    if(reset)
        csr_ecfg_lie <= 13'b0;
    else if(csr_we && csr_num == `CSR_ECFG)
        csr_ecfg_lie <= csr_wmask[`CSR_ECFG_LIE]&csr_wvalue[`CSR_ECFG_LIE]
                      | ~csr_wmask[`CSR_ECFG_LIE]&csr_ecfg_lie;
end

//ESTAT
always @(posedge clk) begin
    if(reset)
        csr_estat_is[1:0] <= 2'b0;
    else if(csr_we && csr_num == `CSR_ESTAT)
        csr_estat_is[1:0] <= csr_wmask[`CSR_ESTAT_IS10]&csr_wvalue[`CSR_ESTAT_IS10]
                          | ~csr_wmask[`CSR_ESTAT_IS10]&csr_estat_is[1:0];
    
    csr_estat_is[9:2] <= hw_int_in[7:0];

    csr_estat_is[10] <= 1'b0;

    if (timer_cnt[31:0]==32'b0)
        csr_estat_is[11] <= 1'b1;
    else if (csr_we && csr_num==`CSR_TICLR && csr_wmask[`CSR_TICLR_CLR] && csr_wvalue[`CSR_TICLR_CLR]) 
        csr_estat_is[11] <= 1'b0;

    csr_estat_is[12] <= ipi_int_in;
end

always @(posedge clk) begin
    if (ws_ex) begin
        csr_estat_ecode <= ws_ecode;
        csr_estat_esubcode <= ws_esubcode;
    end
end

//ERA

always @(posedge clk) begin
    if (ws_ex)
        csr_era_pc <= ws_pc;
    else if (csr_we && csr_num==`CSR_ERA)
        csr_era_pc <= csr_wmask[`CSR_ERA_PC]&csr_wvalue[`CSR_ERA_PC]
                   | ~csr_wmask[`CSR_ERA_PC]&csr_era_pc;
end

//EENTRY
always @(posedge clk) begin
    if (csr_we && csr_num==`CSR_EENTRY)
        csr_eentry_va <= csr_wmask[`CSR_EENTRY_VA]&csr_wvalue[`CSR_EENTRY_VA]
                      | ~csr_wmask[`CSR_EENTRY_VA]&csr_eentry_va;
end

//SAVE
always @(posedge clk) begin
    if (csr_we && csr_num==`CSR_SAVE0)
        csr_save0_data <= csr_wmask[`CSR_SAVE_DATA]&csr_wvalue[`CSR_SAVE_DATA]
                       | ~csr_wmask[`CSR_SAVE_DATA]&csr_save0_data;
    if (csr_we && csr_num==`CSR_SAVE1)
        csr_save1_data <= csr_wmask[`CSR_SAVE_DATA]&csr_wvalue[`CSR_SAVE_DATA]
                       | ~csr_wmask[`CSR_SAVE_DATA]&csr_save1_data;
    if (csr_we && csr_num==`CSR_SAVE2)
        csr_save2_data <= csr_wmask[`CSR_SAVE_DATA]&csr_wvalue[`CSR_SAVE_DATA]
                       | ~csr_wmask[`CSR_SAVE_DATA]&csr_save2_data;
    if (csr_we && csr_num==`CSR_SAVE3)
        csr_save3_data <= csr_wmask[`CSR_SAVE_DATA]&csr_wvalue[`CSR_SAVE_DATA]
                       | ~csr_wmask[`CSR_SAVE_DATA]&csr_save3_data;
end

//TCFG
always @(posedge clk) begin
    if (reset)
        csr_tcfg_en <= 1'b0;
    else if (csr_we && csr_num==`CSR_TCFG)
        csr_tcfg_en <= csr_wmask[`CSR_TCFG_EN]&csr_wvalue[`CSR_TCFG_EN] 
                    | ~csr_wmask[`CSR_TCFG_EN]&csr_tcfg_en;
    
    if (csr_we && csr_num==`CSR_TCFG) begin
        csr_tcfg_periodic <= csr_wmask[`CSR_TCFG_PERIOD]&csr_wvalue[`CSR_TCFG_PERIOD]
                          | ~csr_wmask[`CSR_TCFG_PERIOD]&csr_tcfg_periodic;
        csr_tcfg_initval  <= csr_wmask[`CSR_TCFG_INITV]&csr_wvalue[`CSR_TCFG_INITV]
                          | ~csr_wmask[`CSR_TCFG_INITV]&csr_tcfg_initval;
    end
end

//TVAL
assign tcfg_next_value = csr_wmask[31:0]&csr_wvalue[31:0]
                       | ~csr_wmask[31:0]&{csr_tcfg_initval,csr_tcfg_periodic, csr_tcfg_en};

always @(posedge clk) begin
    if (reset)
        timer_cnt <= 32'hffffffff;
    else if (csr_we && csr_num==`CSR_TCFG && tcfg_next_value[`CSR_TCFG_EN])
        timer_cnt <= {tcfg_next_value[`CSR_TCFG_INITVAL], 2'b0};
    else if (csr_tcfg_en && timer_cnt!=32'hffffffff) begin
            if (timer_cnt[31:0]==32'b0 && csr_tcfg_periodic)
                timer_cnt <= {csr_tcfg_initval, 2'b0};
            else
                timer_cnt <= timer_cnt - 1'b1;
    end
end

assign csr_tval_timeval = timer_cnt[31:0];

//TICLR
assign csr_ticlr_clr = 1'b0;

// default
// assign csr_crmd_da = 1'b1;
// assign csr_crmd_pg = 1'b1;

// read out value select
assign csr_crmd_rvalue      = {27'b0, csr_crmd_pg, csr_crmd_da, csr_crmd_ie, csr_crmd_plv};
assign csr_prmd_rvalue      = {29'b0, csr_prmd_pie, csr_prmd_pplv};
assign csr_ecfg_rvalue      = {19'b0, csr_ecfg_lie};
assign csr_estat_rvalue     = {1'b0, csr_estat_esubcode, csr_estat_ecode, 3'b0, csr_estat_is};
assign csr_era_rvalue       = csr_era_pc;
assign csr_badv_rvalue      = csr_badv_vaddr;
assign csr_eentry_rvalue    = {csr_eentry_va, 6'b0};
assign csr_save0_rvalue     = csr_save0_data;
assign csr_save1_rvalue     = csr_save1_data;
assign csr_save2_rvalue     = csr_save2_data;
assign csr_save3_rvalue     = csr_save3_data;
assign csr_tid_rvalue       = csr_tid_tid;
assign csr_tcfg_rvalue      = {csr_tcfg_initval, csr_tcfg_periodic, csr_tcfg_en};
assign csr_tval_rvalue      = csr_tval_timeval;
assign csr_ticlr_rvalue     = {31'b0, csr_ticlr_clr};

assign csr_rvalue = {32{csr_num == `CSR_CRMD  }}    & csr_crmd_rvalue
                  | {32{csr_num == `CSR_PRMD  }}    & csr_prmd_rvalue 
                  | {32{csr_num == `CSR_ECFG  }}    & csr_ecfg_rvalue
                  | {32{csr_num == `CSR_ESTAT }}    & csr_estat_rvalue
                  | {32{csr_num == `CSR_ERA   }}    & csr_era_rvalue
                  | {32{csr_num == `CSR_BADV  }}    & csr_badv_rvalue
                  | {32{csr_num == `CSR_EENTRY}}    & csr_eentry_rvalue
                  | {32{csr_num == `CSR_SAVE0 }}    & csr_save0_rvalue
                  | {32{csr_num == `CSR_SAVE1 }}    & csr_save1_rvalue
                  | {32{csr_num == `CSR_SAVE2 }}    & csr_save2_rvalue
                  | {32{csr_num == `CSR_SAVE3 }}    & csr_save3_rvalue
                  | {32{csr_num == `CSR_TID   }}    & csr_tid_rvalue
                  | {32{csr_num == `CSR_TCFG  }}    & csr_tcfg_rvalue
                  | {32{csr_num == `CSR_TVAL  }}    & csr_tval_rvalue
                  | {32{csr_num == `CSR_TICLR }}    & csr_ticlr_rvalue;

assign has_int = ((csr_estat_is[11:0] & csr_ecfg_lie[11:0]) != 12'b0) 
                && (csr_crmd_ie == 1'b1);

assign ex_entry = csr_eentry_rvalue;
assign era_entry = csr_era_rvalue;


endmodule