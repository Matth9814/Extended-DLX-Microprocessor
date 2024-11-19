library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;
use WORK.constants.all;
use IEEE.math_real.all;

-- the D2E regs must be reset when the D2E_en is low: that is because otherwise
-- there would be an operation detected (since the detection relies on the bit of
-- the ALU_op field).
-- TODO: ALL THE INSTRUCTIONS SHOULD LEAVE THE DECODE FROM THE SECOND STAGE, SO THERE IS AN
-- ACTUAL ADDITIONAL STAGE IN THE PIPELINE (which we should call DEC1).
-- TODO: CONSIDER THAT THE BUSY SIGNALS ARE NOT UPDATED WHEN THE INSTRUCTION WHICH LEFT THE RS IS STILL IN
-- THE RS_OUTPUT2 STAGE! A SIMPLE WAY TO PREVENT THE INSTRUCTION IN THIS SECOND STAGE FROM INTERFERING WITH
-- THE CONDITION DETERMINED WHEN THE SECOND INSTRUCTION LEAVES THE RS IS THE ONE TO AVOID OUTPUTTING TWO INSTRUCTION
-- OF THE SAME KIND ONE AFTER THE OTHER, but this requires additional logic in the rs which would complicate the prio encoder.
-- --> you can act on the busy signals by masking them with a 0 if there is an instruction of the same type in the RS_output2.

entity dlx_datapath is
    generic (
        PAR: natural := 32; -- parallelism, size of registers
        CW_SIZE: natural :=32 -- size of the control word
    );
    port (
        -- general signals for the circuit
        rst: in std_logic;
        clk: in std_logic;

        -- enable and clear signals for the datapath pipeline registers (driven by the HU)
        F2D_en: in std_logic;
        F2D_clr: in std_logic;
        D2E_clr: in std_logic;
        E2M_clr: in std_logic;
        M2WB_clr: in std_logic;

        -- control signals from the CU
        ALU_unit: in std_logic_vector(4 downto 0);
        rw_dmem: in std_logic; -- to select if a read or a write has to be performed in the dmem
        OpA_sel: in std_logic; -- to select the first operand to the ALU
        OpB_sel: in std_logic; -- to select the second operand to the ALU
        ALU_op: in std_logic_vector(4 downto 0); -- selector for ALU operation
        beqz_or_bnez: in std_logic; -- to identify if the branch instruction is a beqz_or_bnez
        is_branch: in std_logic; -- 1 if the instruction is a branch
        res_sel: in std_logic_vector (1 downto 0); -- to select a result between the output of the ALU and the one of the memory
        w_reg: in std_logic; -- 1 if we have to write a result in the RF (write enable for the register file)
        dest_sel: in std_logic_vector(1 downto 0); -- to select the destination register for the write
        is_unconditional_branch: in std_logic; -- 1 if the branch is unconditional
        -- we need two enable signals because the RF is used both in D and WB: if at least one of them is active
        -- then the register file will be active
        D_rf_en: in std_logic; -- enable for the register file from the instruction in the decode stage
        WB_rf_en: in std_logic; -- enable for the register file from the instruction in the writeback stage
        rf_rd1_en: in std_logic; -- enable for the first read port
        rf_rd2_en: in std_logic; -- enable for the second read port

        -- signals to identify the type of operation
        RIJ: in std_logic_vector(1 downto 0);

        -- signals from datapath to CU
        DEC2_ALU_unit: out std_logic_vector(4 downto 0);
        opcode: out std_logic_vector(5 downto 0);
        func: out std_logic_vector(10 downto 0);
        is_mispredicted: out std_logic;
        rob_full: out std_logic;
        rs_full: out std_logic;
        haz_neg: out std_logic;
        add_busy: out std_logic;
        logicals_busy: out std_logic;
        shifter_busy: out std_logic;
        mul_busy: out std_logic;
        div_busy: out std_logic;
        ins_is_leaving: out std_logic;

        -- signals between datapath and data memory
        address_DM_read: out std_logic_vector(PAR-1 downto 0);
        address_DM_write: out std_logic_vector(PAR-1 downto 0);
        data_to_DM: out std_logic_vector(PAR-1 downto 0);
        data_from_DM: in std_logic_vector(PAR-1 downto 0); 
        rw_to_DM: out std_logic; 

        -- signals from datapath to instruction memory
        address_IM: out std_logic_vector(PAR-1 downto 0);
        data_from_IM: in std_logic_vector(PAR-1 downto 0);

        -- signal from CU to dp to determine if the instruction in decode is ready to leave
        dec_ready: in std_logic

    );
end dlx_datapath;

-- PROOF OF CONCEPT ALERT: REPLACE THE COMPONENTS WITH THE ONES THAT WE ACTUALLY IMPLEMENTED
architecture dataflow_dp of dlx_datapath is

    signal PC_next: std_logic_vector(PAR-1 downto 0);
    signal PC_curr: std_logic_vector(PAR-1 downto 0);
    signal PC_plus4: std_logic_vector(PAR-1 downto 0);
    signal PC_computed: std_logic_vector(PAR-1 downto 0);
    signal reg_to_write: std_logic_vector(4 downto 0); -- the register where we write in the RF
    signal data_to_write: std_logic_vector(PAR-1 downto 0); -- the data to write in this register, it is the output of the MUX in the WB stage
    signal RF_out1: std_logic_vector(PAR-1 downto 0); -- outputs of the register file
    signal RF_out2: std_logic_vector(PAR-1 downto 0);
    signal ALU_in1: std_logic_vector(PAR-1 downto 0); -- inputs of the ALU
    signal ALU_in2: std_logic_vector(PAR-1 downto 0);    
    signal branch_outcome: std_logic; -- the output of the MUX in the memory stage
    signal bypass_detection_RA: std_logic; -- to have low power consumption in the circuit for detecting wb-d conflicts
    signal bypass_detection_RB: std_logic; -- to have low power consumption in the circuit for detecting wb-d conflicts
    signal branch_evaluation_mux_out: std_logic_vector(PAR-1 downto 0);

    -- pipeline registers
    signal F2D_IR_curr: std_logic_vector(PAR-1 downto 0);
    signal F2D_PCN_curr: std_logic_vector(PAR-1 downto 0);
    signal F2D_pred_curr: std_logic;
    signal D2E_regA_curr: std_logic_vector(PAR-1 downto 0);
    signal D2E_regB_curr: std_logic_vector(PAR-1 downto 0);
    signal D2E_IR_curr: std_logic_vector(PAR-1 downto 0);
    signal D2E_PCN_curr: std_logic_vector(PAR-1 downto 0);
    signal D2E_imm_curr: std_logic_vector(PAR-1 downto 0);
    signal D2E_control_curr: std_logic_vector(CW_SIZE-1 downto 0); -- control word
    signal D2E_pred_curr: std_logic;
    signal D2E_ROB_entry_curr: std_logic_vector(5 downto 0);
    signal D2E_valid_bit_curr: std_logic;
    signal E2M_ALUres_curr: std_logic_vector(PAR-1 downto 0);
    signal E2M_PCN_curr: std_logic_vector(PAR-1 downto 0); -- for branches
    signal E2M_regB_curr: std_logic_vector(PAR-1 downto 0);
    signal E2M_IR_curr: std_logic_vector(PAR-1 downto 0);
    signal E2M_control_curr: std_logic_vector(CW_SIZE-1 downto 0); -- control word
    signal E2M_branchres_curr: std_logic; -- result of the branch (beqz, bnez)
    signal E2M_pred_curr: std_logic;
    signal E2M_ROB_entry_curr: std_logic_vector(5 downto 0);
    signal E2M_valid_bit_curr: std_logic;
    signal M2WB_IR_curr: std_logic_vector(PAR-1 downto 0);
    signal M2WB_memres_curr: std_logic_vector(PAR-1 downto 0);
    signal M2WB_ALUres_curr: std_logic_vector(PAR-1 downto 0);
    signal M2WB_control_curr: std_logic_vector(CW_SIZE-1 downto 0); -- control word
    signal M2WB_PCN_curr: std_logic_vector(PAR-1 downto 0);
    signal M2WB_ROB_entry_curr: std_logic_vector(5 downto 0);
    signal M2WB_valid_bit_curr: std_logic;
    signal M2WB_branchres_curr: std_logic;
    signal M2WB_regb_curr: std_logic_vector(31 downto 0);

    signal F2D_IR_next: std_logic_vector(PAR-1 downto 0);
    signal F2D_PCN_next: std_logic_vector(PAR-1 downto 0);
    signal D2E_regA_next: std_logic_vector(PAR-1 downto 0);
    signal D2E_regB_next: std_logic_vector(PAR-1 downto 0);
    signal D2E_IR_next: std_logic_vector(PAR-1 downto 0);
    signal D2E_PCN_next: std_logic_vector(PAR-1 downto 0);
    signal D2E_imm_next: std_logic_vector(PAR-1 downto 0);
    signal D2E_control_next: std_logic_vector(CW_SIZE-1 downto 0); -- control word
    signal D2E_pred_next: std_logic;
    signal E2M_ALUres_next: std_logic_vector(PAR-1 downto 0);
    signal E2M_PCN_next: std_logic_vector(PAR-1 downto 0); -- for branches
    signal E2M_regB_next: std_logic_vector(PAR-1 downto 0);
    signal E2M_IR_next: std_logic_vector(PAR-1 downto 0);
    signal E2M_control_next: std_logic_vector(CW_SIZE-1 downto 0); -- control word
    signal E2M_branchres_next: std_logic; -- result of the branch (beqz, bnez)
    signal E2M_pred_next: std_logic;
    signal E2M_ROB_entry_next: std_logic_vector(5 downto 0);
    signal M2WB_IR_next: std_logic_vector(PAR-1 downto 0);
    signal M2WB_memres_next: std_logic_vector(PAR-1 downto 0);
    signal M2WB_ALUres_next: std_logic_vector(PAR-1 downto 0);
    signal M2WB_control_next: std_logic_vector(CW_SIZE-1 downto 0); -- control word
    signal M2WB_PCN_next: std_logic_vector(PAR-1 downto 0);
    signal M2WB_ROB_entry_next: std_logic_vector(5 downto 0);
    signal M2WB_branchres_next: std_logic;
    signal M2WB_regb_next: std_logic_vector(31 downto 0);

    -- execute stage control signals
    signal E_rw_dmem: std_logic;
    signal E_OpA_sel: std_logic;
    signal E_OpB_sel: std_logic;
    signal E_ALU_op: std_logic_vector(4 downto 0);
    signal E_beqz_or_bnez: std_logic;
    signal E_is_branch: std_logic;
    signal E_res_sel: std_logic_vector(1 downto 0);
    signal E_w_reg: std_logic;
    signal E_dest_sel: std_logic_vector(1 downto 0);
    signal E_is_unconditional_branch: std_logic;
    signal E_RIJ: std_logic_vector(1 downto 0);

    -- memory stage control signals
    signal M_rw_dmem: std_logic;
    signal M_OpA_sel: std_logic;
    signal M_OpB_sel: std_logic;
    signal M_ALU_op: std_logic_vector(4 downto 0);
    signal M_beqz_or_bnez: std_logic;
    signal M_is_branch: std_logic;
    signal M_res_sel: std_logic_vector(1 downto 0);
    signal M_w_reg: std_logic;
    signal M_dest_sel: std_logic_vector(1 downto 0);
    signal M_is_unconditional_branch: std_logic;
    signal M_RIJ: std_logic_vector(1 downto 0);

    -- write-back stage control signals
    signal WB_rw_dmem: std_logic;
    signal WB_OpA_sel: std_logic;
    signal WB_OpB_sel: std_logic;
    signal WB_ALU_op: std_logic_vector(4 downto 0);
    signal WB_beqz_or_bnez: std_logic;
    signal WB_is_branch: std_logic;
    signal WB_res_sel: std_logic_vector(1 downto 0);
    signal WB_w_reg: std_logic;
    signal WB_dest_sel: std_logic_vector(1 downto 0);
    signal WB_is_unconditional_branch: std_logic;
    signal WB_RIJ: std_logic_vector(1 downto 0);

    -- signals from the instruction memory to the datapath
    signal instruction: std_logic_vector(PAR-1 downto 0); 

    signal is_mispredicted_internal: std_logic;
    signal taken: std_logic;
    signal predicted_target: std_logic_vector(PAR-1 downto 0);
    signal jmp_addr: std_logic_vector(PAR-1 downto 0);
    signal rf_en: std_logic;

    -- ROB related signals
    signal ROB_res: std_logic_vector(PAR-1 downto 0);
    signal ROB_regb: std_logic_vector(PAR-1 downto 0); -- value for regb, used by store instructions
    signal ROB_pred: std_logic; -- prediction per l'istruzione salto in uscita dal ROB
    signal ROB_PCN_out: std_logic_vector(PAR-1 downto 0);
    signal ROB_out1: std_logic_vector(PAR-1 downto 0);
    signal ROB_out2: std_logic_vector(PAR-1 downto 0);
    signal ROB_out1_valid: std_logic;
    signal ROB_out2_valid: std_logic;
    signal newline: std_logic_vector(5 downto 0);
    signal strike_len: std_logic_vector(6 downto 0);
    signal reg_modified: std_logic_vector(4 downto 0);
    signal to_be_written: std_logic;
    signal deleted_rob_entry: std_logic_vector(5 downto 0);
    signal ROB_en_line: std_logic;
    signal ROB_RD3_pred_out: std_logic;
    signal ROB_RD3_ctrl_out: std_logic_vector(PAR-1 downto 0);
    signal ROB_RD3_IR_out: std_logic_vector(PAR-1 downto 0);
    signal ROB_RD3_PCN_out: std_logic_vector(PAR-1 downto 0);
    signal ROB_RD3_regb_out: std_logic_vector(PAR-1 downto 0);
    signal ROB_in1: std_logic_vector(5 downto 0);
    signal ROB_in2: std_logic_vector(5 downto 0);
    signal ROB_in5: std_logic_vector(5 downto 0);
    signal ROB_in6: std_logic_vector(5 downto 0);
    signal ROB_out5: std_logic_vector(PAR-1 downto 0);
    signal ROB_out6: std_logic_vector(PAR-1 downto 0);
    
    -- RAT related signals
    signal WR2_mux_RAT: std_logic_vector(4 downto 0);
    signal RAT_out1: std_logic_vector(5 downto 0);
    signal RAT_out2: std_logic_vector(5 downto 0);
    signal RAT_out1_valid: std_logic;
    signal RAT_out2_valid: std_logic;
    signal RAT_inv: std_logic;
    signal RAT_WR2_en: std_logic;
    
    -- wasteland
    signal RF_WR: std_logic;
    signal bypass_detection_RA_before_ROB: std_logic;
    signal bypass_detection_RB_before_ROB: std_logic;
    signal ins_is_nop: std_logic;
    signal ins_is_exit: std_logic;
    signal mux_RF_ROB_A: std_logic_vector(PAR-1 downto 0);
    signal mux_RF_ROB_B: std_logic_vector(PAR-1 downto 0);
    signal op1_available: std_logic;
    signal op2_available: std_logic;
    signal operands_available: std_logic;
    signal I_type_mux_out: std_logic;
    signal D2E_rst: std_logic;
    signal E2M_rst: std_logic;
    signal M2WB_rst: std_logic;
    signal operands_available_or_NOP: std_logic;
    signal E2M_en: std_logic;
    signal M2WB_en: std_logic;
    signal terminal_cnt: std_logic;
    signal ctrl_word_out_dbg: std_logic_vector(31 downto 0);
    signal ALUres_mux_out: std_logic_vector(31 downto 0);
    signal load_busy_ff: std_logic;
    signal ALUres_reg_curr: std_logic_vector(31 downto 0);
    signal regB_mux_out: std_logic_vector(31 downto 0);
    signal mux_en_to_WB: std_logic;
    signal regB_reg_curr: std_logic_vector(31 downto 0);
    signal control_reg_curr: std_logic_vector(31 downto 0);
    signal PCN_reg_curr: std_logic_vector(31 downto 0);
    signal IR_reg_curr: std_logic_vector(31 downto 0);
    signal branchres_reg_curr: std_logic;
    signal rob_entry_reg_curr: std_logic_vector(5 downto 0);
    signal ROB_mem_w_en: std_logic;
    signal CAM_next_inval: std_logic;
    signal CAM_match: std_logic;
    signal CAM_out: std_logic;
    signal not_in_load_exit_cycle: std_logic;
    signal is_store: std_logic;
    signal is_load: std_logic;
    signal mux_en_to_WB_registers: std_logic;
    signal F2D_en_curr_ROB: std_logic;
    signal F2D_en_curr_RS: std_logic;
    signal D2E_control_next_int: std_logic_vector(PAR-1 downto 0);
    signal D2E_regb_next_int: std_logic_vector(PAR-1 downto 0);
    signal RF_in1: std_logic_vector(4 downto 0);
    signal RF_in2: std_logic_vector(4 downto 0);
    signal F2D_valid_and_not_NOP: std_logic;
    signal op1_rob_or_rf: std_logic_vector(5 downto 0);
    signal op2_rob_or_rf: std_logic_vector(5 downto 0);
    signal RS_new_valid_op1: std_logic_vector(1 downto 0);
    signal RS_new_valid_op2: std_logic_vector(1 downto 0);
    signal RS_ins_leaving: std_logic;
    signal RS_rob_entry_leaving: std_logic_vector(5 downto 0);
    signal RS_rob_valid_op1: std_logic_vector(1 downto 0);
    signal RS_rob_valid_op2: std_logic_vector(1 downto 0);
    signal RS_rob_rf_entry_op1: std_logic_vector(5 downto 0);
    signal RS_rob_rf_entry_op2: std_logic_vector(5 downto 0);
    signal add_busy_int: std_logic;
    signal logicals_busy_int: std_logic;
    signal shifter_busy_int: std_logic;
    signal mul_busy_int: std_logic;
    signal div_busy_int: std_logic;
    signal ins_type_from_ALU_OP: std_logic_vector(2 downto 0);
    signal ROB_allocation_done: std_logic;
    signal RS_allocation_done: std_logic;
    signal D2E_en: std_logic;
    signal RS_new_ins: std_logic;
    signal haz_neg_with_RS: std_logic;
    signal D2E_regA_next_int: std_logic_vector(PAR-1 downto 0);
    signal D2E_imm_next_int: std_logic_vector(PAR-1 downto 0);
    signal D2E_IR_next_int: std_logic_vector(PAR-1 downto 0);
    signal D2E_PCN_next_int: std_logic_vector(PAR-1 downto 0);
    signal D2E_pred_next_int: std_logic;
    signal ROB_RD4_instruction: std_logic_vector(PAR-1 downto 0);
    signal ROB_RD4_control: std_logic_vector(PAR-1 downto 0);
    signal ROB_RD4_PCN: std_logic_vector(PAR-1 downto 0);
    signal ROB_RD4_pred: std_logic;
    signal D2E_imm_next_RS: std_logic_vector(PAR-1 downto 0);
    signal D2E_IR_next_RS: std_logic_vector(PAR-1 downto 0);
    signal D2E_PCN_next_RS: std_logic_vector(PAR-1 downto 0);
    signal D2E_control_next_RS: std_logic_vector(PAR-1 downto 0);
    signal D2E_regA_next_RS: std_logic_vector(PAR-1 downto 0);
    signal D2E_pred_next_RS: std_logic;
    signal D2E_regB_next_RS: std_logic_vector(PAR-1 downto 0);
    signal D2E_ROB_entry_next: std_logic_vector(5 downto 0);
    signal rob_full_int: std_logic;
    signal ROB_RD4: std_logic_vector(161 downto 0);
    signal next_D2E_is_NOP: std_logic;
    signal ROB_WR3_en: std_logic;
    signal ROB_entry_to_delete: std_logic_vector(5 downto 0);
    signal WB_instruction_is_head: std_logic;
    signal ROB_head_ready: std_logic;
    signal rob_entry_store_reg_curr: std_logic_vector(5 downto 0);
    signal ROB_entry_eq_ROB_entry_mux_out: std_logic;
    signal ROB_entry_mux_out: std_logic_vector(5 downto 0);
    signal CAM_rob_entry: std_logic_vector(5 downto 0);
    signal ROB_regb_store: std_logic_vector(PAR-1 downto 0);
    signal ROB_res_eq_ALUres: std_logic;
    signal ROB_res_curr: std_logic_vector(PAR-1 downto 0);
    signal committed_ROB_entry_eq_CAM_ROB_entry: std_logic;
    signal deleted_rob_entry_curr: std_logic_vector(5 downto 0);
    signal committed_in_first_cycle: std_logic;
    signal committed_in_first_cycle_curr: std_logic;
    signal CAM_match_curr: std_logic;
    signal CAM_w_en: std_logic;
    signal ROB_mem_w_en_curr: std_logic;
    signal valid_load_curr: std_logic;
    signal CAM_rob_entry_curr: std_logic_vector(5 downto 0);
    signal ROB_regb_curr: std_logic_vector(PAR-1 downto 0);
    signal F2D_en_int: std_logic;
    signal DEC2_ins_is_NOP: std_logic;
    signal DEC2_IR_curr: std_logic_vector(PAR-1 downto 0);
    signal DEC2_IR_next: std_logic_vector(PAR-1 downto 0);
    signal DEC2_ROB_line_next: std_logic_vector(5 downto 0);
    signal DEC2_ROB_line_curr: std_logic_vector(5 downto 0);
    signal RAT_out1_eq_ROB_committed: std_logic;
    signal RAT_out2_eq_ROB_committed: std_logic;
    signal DEC2_RAT_out1_valid_next: std_logic;
    signal DEC2_RAT_out2_valid_next: std_logic;
    signal RS_tc: std_logic_vector(4 downto 0);
    signal dec1_to_dec2_en: std_logic;
    signal dec1_to_dec2_rst: std_logic;
    signal RS_output2_rob_entry_leaving_next: std_logic_vector(5 downto 0);
    signal RS_output2_rob_valid_op1_next: std_logic_vector(1 downto 0);
    signal RS_output2_rob_valid_op2_next: std_logic_vector(1 downto 0);
    signal RS_output2_rob_rf_entry_op1_next: std_logic_vector(5 downto 0);
    signal RS_output2_rob_rf_entry_op2_next: std_logic_vector(5 downto 0);
    signal RS_output2_en: std_logic;
    signal RS_output2_rst: std_logic;
    signal RS_output2_ins_leaving: std_logic;
    signal RS_ins_leaving_any_phase: std_logic;
    signal DEC2_ALU_unit_int: std_logic_vector(4 downto 0);
    signal DEC2_RAT_out1_valid: std_logic;
    signal DEC2_RAT_out2_valid: std_logic;
    signal DEC2_RAT_out1: std_logic_vector(5 downto 0);
    signal DEC2_RAT_out2: std_logic_vector(5 downto 0);
    signal DEC2_RIJ: std_logic_vector(1 downto 0);
    signal DEC2_rw_dmem: std_logic;
    signal DEC2_imm_next: std_logic_vector(PAR-1 downto 0);
    signal DEC2_imm_curr: std_logic_vector(PAR-1 downto 0);
    signal DEC2_PCN_next: std_logic_vector(PAR-1 downto 0);
    signal DEC2_PCN_curr: std_logic_vector(PAR-1 downto 0);
    signal DEC2_pred_curr: std_logic;
    signal DEC2_pred_next: std_logic;
    signal DEC2_control_curr: std_logic_vector(PAR-1 downto 0);
    signal DEC2_control_next: std_logic_vector(PAR-1 downto 0);
    signal E_ALU_unit: std_logic_vector(4 downto 0);
    signal ALU_Cout: std_logic;
    signal E2M_carry_out_next: std_logic;
    signal E2M_carry_out_curr: std_logic;
    signal CMP_sne: std_logic;
    signal CMP_sle: std_logic;
    signal CMP_sge: std_logic;
    signal CMP_res: std_logic_vector(PAR-1 downto 0);
    signal E2M_ALUres_withCMP: std_logic_vector(PAR-1 downto 0);
    signal DEC2_OpA_sel: std_logic;
    signal DEC2_OpB_sel: std_logic;
    signal DEC2_ALU_op: std_logic_vector(4 downto 0);
    signal DEC2_beqz_or_bnez: std_logic;
    signal DEC2_is_branch: std_logic;
    signal DEC2_res_sel: std_logic_vector(1 downto 0);
    signal DEC2_dest_sel: std_logic_vector(1 downto 0);
    signal DEC2_w_reg: std_logic;
    signal DEC2_is_unconditional_branch: std_logic;
    signal RS_full_int: std_logic;
    signal DEC1_ins_type_from_ALU_OP: std_logic_vector(2 downto 0);
    signal RS_output2_rob_entry_leaving_curr: std_logic_vector(5 downto 0);
    signal RS_output2_rob_valid_op1_curr: std_logic_vector(1 downto 0);
    signal RS_output2_rob_valid_op2_curr: std_logic_vector(1 downto 0);
    signal RS_output2_rob_rf_entry_op1_curr: std_logic_vector(5 downto 0);
    signal RS_output2_rob_rf_entry_op2_curr: std_logic_vector(5 downto 0);
    signal RS_output2_type_of_ins_leaving_curr: std_logic_vector(4 downto 0);
    signal RS_output2_type_of_ins_leaving_next: std_logic_vector(4 downto 0);
    signal add_busy_with_rs_output2: std_logic;
    signal logicals_busy_with_rs_output2: std_logic;
    signal shifter_busy_with_rs_output2: std_logic;
    signal mul_busy_with_rs_output2: std_logic;
    signal div_busy_with_rs_output2: std_logic;
    signal RS_type_of_ins_leaving: std_logic_vector(4 downto 0);
    signal memory_involved: std_logic;

    -- simple register file: change it to integrate windowing
    component register_file is
        generic(NREG: natural := numReg;
                NBIT: natural := numBitReg);
        port ( CLK: 	IN std_logic;
               RESET: 	IN std_logic;
               ENABLE: 	IN std_logic;
               RD1: 	IN std_logic;		-- sel data out 1
               RD2: 	IN std_logic;		-- sel data out 2
               WR: 		IN std_logic;			-- sel data in
               ADD_WR: 	IN std_logic_vector(natural(ceil(log2(real(NREG))))-1 downto 0);	-- log2 NREGISTER
               ADD_RD1: IN std_logic_vector(natural(ceil(log2(real(NREG))))-1 downto 0);	-- log2 NREGISTER
               ADD_RD2: IN std_logic_vector(natural(ceil(log2(real(NREG))))-1 downto 0);	-- log2 NREGISTER
               DATAIN: 	IN std_logic_vector(NBIT-1 downto 0);	-- one write port
               OUT1: 	OUT std_logic_vector(NBIT-1 downto 0);	-- two read port
               OUT2: 	OUT std_logic_vector(NBIT-1 downto 0));	-- two read port
    end component;

    component ALU is 
        generic(
            SIZE: natural := PAR
        );
        port(
            inp1: in std_logic_vector(PAR-1 downto 0); -- input 1 for the ALU
            inp2: in std_logic_vector(PAR-1 downto 0); -- input 2 for the ALU
            op: in std_logic_vector(4 downto 0); -- ALU_op, provided by the CU
            unit: in std_logic_vector(4 downto 0); -- one hot representation of the unit where the operation will be performed
            res: out std_logic_vector(PAR-1 downto 0); -- result on 32 bits
            carry_out: out std_logic; -- carry out from the adder
            rst: in std_logic; -- synchronous reset, driven by the clear signal for the pipeline registers
            h_rst: in std_logic; -- async reset, the one used to reset the whole core
            terminal_cnt: out std_logic; -- terminal count, used as a validity bit to tell if a new instruction has to be written in the E2M register
            clk: in std_logic;
            divType: in std_logic; -- for the type of division (1 signed, 0 unsigned)

            -- control information for the current instruction (input)
            ins_in: in std_logic_vector(PAR-1 downto 0); -- instruction entering the ALU, needed because load must be stalled in the ALU when there is already a load in memory waiting for its operand
            ROB_entry_in: in std_logic_vector(5 downto 0);  -- ROB index of the instruction
            is_branch: in std_logic; -- 1 if the incoming instruction is a branch
            beqz_or_bnez: in std_logic; -- 1 if the incoming instruction is a bnez, otherwise it is 0

            -- busy signals for the internal units, sent to the CU to determine if the instruction is decode is free to pass : if the corresponding unit is full, then the instruction is stalled in dec
            add_busy: out std_logic; 
            logicals_busy: out std_logic;
            shifter_busy: out std_logic;
            mul_busy: out std_logic;
            div_busy: out std_logic;

            -- ROB entry of the instruction that is leaving, additional data will be retrieved from the ROB when the instruction leaves the execute stage (it saves space)
            ROB_entry_out: out std_logic_vector(5 downto 0);
            branchres_out: out std_logic;

            inp_branch: in std_logic_vector(PAR-1 downto 0)
        );
    end component;

    component BTB is
        port(
            addr: in std_logic_vector(7 downto 0);
            target: in std_logic_vector(31 downto 0);
            jmp_addr: in std_logic_vector(31 downto 0);
            res: in std_logic; -- result of the branch
            rw: in std_logic; -- rw is 1 if the branch is mispredicted
            clk: in std_logic;
            rst: in std_logic;
            taken: out std_logic;
            predicted_target: out std_logic_vector(31 downto 0)
        );
    end component;

    component RAT is
        port(
            RD1: in std_logic_vector(4 downto 0); -- first operand
            RD2: in std_logic_vector(4 downto 0); -- second operand
            WR2: in std_logic_vector(4 downto 0); -- register where the result has to be written, updated in decode
            WR1: in std_logic_vector(4 downto 0); -- register where the result of the istruction in writeback has to be written, modified during commit
            inp: in std_logic_vector(5 downto 0); -- ROB entry associated to WR2 register
            inv: in std_logic; -- 1 if the entry corresponding to WR1 must be invalidated (during the commit phase)
            WR2_en: in std_logic; -- 1 if the entry corresponding to WR2 must be overwritten with inp (during decode and ROB allocation)
            clk: in std_logic;
            rst: in std_logic; -- raised when there is the commit of a mispredicted branch
            h_rst: in std_logic; -- reset of the whole core
            rob_entry_to_be_deleted: in std_logic_vector(5 downto 0); -- WR1 entry is invalidated only if its content is equal to this input
    
            out1: out std_logic_vector(5 downto 0); -- rob entry associated to the first operand
            out2: out std_logic_vector(5 downto 0); -- rob entry associated to the second operand
            out1_valid: out std_logic; -- 1 if the RD1 entry is valid in the RAT
            out2_valid: out std_logic -- 1 if the RD2 entry is valid in the RAT
    
        );
    end component;

    component ROB is
        port(
            WR1: in std_logic_vector(5 downto 0); -- ROB entry of the instruction to be committed (to be deleted from the ROB)
            inval: in std_logic; -- 1 if the instruction in the WR1 entry has to be deleted
    
            WR2: in std_logic_vector(5 downto 0); -- ROB entry of the instruction that is terminating in writeback
            ins_terminated: in std_logic; -- 1 if there is a new instruction in write-back
            ins_res: in std_logic_vector(PAR-1 downto 0); -- result produced by the instruction that is terminating
            branch_res: in std_logic; -- result of the branch
            WR3: in std_logic_vector(5 downto 0); -- 3rd write port, used to write the value of the second operand for the instruction which is leaving the decode
            WR3_en: in std_logic; -- high when one instruction (not nop) is leaving the decode 
            regb: in std_logic_vector(PAR-1 downto 0); -- value for regb of the instruction that is being committed, it is used by sw to store data in memory
            
            RD1: in std_logic_vector(5 downto 0); -- ROB entry associated to the first operand
            RD2: in std_logic_vector(5 downto 0); -- ROB entry associated to the second operand
            RD3: in std_logic_vector(5 downto 0); -- ROB entry associated to the instruction which is leaving the execution stage
            RD4: in std_logic_vector(5 downto 0); -- ROB entry associated to the instruction that is leaving the reservation stations
            RD5: in std_logic_vector(5 downto 0); -- ROB entry corresponding to the instruction which produces the first operand for the instruction coming from the RS
            RD6: in std_logic_vector(5 downto 0); -- as before, but for the second operand
            RD7: in std_logic_vector(5 downto 0); -- ROB entry corresponding to the store instruction which wrote data in the memory address that a load is trying to read
            
            WR_line: in std_logic_vector(PAR-1 downto 0); -- instruction to be allocated in a new rob entry
            en_line: in std_logic; -- if the allocation of the new line has to be performed (so that it is not perfomed twice when the decode is stalling)
            WR_ctrl_word: in std_logic_vector(PAR-1 downto 0); -- ctrl word of the instruction to be allocated
            branch_prediction: in std_logic; -- branch prediction for the newly allocated instruction
            PCN: in std_logic_vector(PAR-1 downto 0);
    
            clk: in std_logic;
            rst: in std_logic; -- when a branch is mispredicted the whole ROB must be freed
            h_rst: in std_logic; -- reset of the core
    
            read_line: in std_logic; -- 1 if the line indexed by WR1 must be read (every time we perform a commit, because we need to check if the RAT must be invalidated or if a jump must be evaluated)
    
            -- outputs related to the instruction leaving the execution stage
            IR_out_exec: out std_logic_vector(PAR-1 downto 0);
            ctrl_out_exec: out std_logic_vector(PAR-1 downto 0);
            PCN_out_exec: out std_logic_vector(PAR-1 downto 0);
            pred_out_exec: out std_logic;
    
            allocation_done: out std_logic;
            out1: out std_logic_vector(PAR-1 downto 0); -- value of the register RD1
            out1_valid: out std_logic; -- 1 if the out1 is a valid value 
            out2: out std_logic_vector(PAR-1 downto 0); -- value of the register RD2
            out2_valid: out std_logic; -- 1 if the out2 is a valid value
            out5: out std_logic_vector(PAR-1 downto 0);
            out6: out std_logic_vector(PAR-1 downto 0);
            out7: out std_logic_vector(PAR-1 downto 0);
            RD4_out_line: out std_logic_vector(161 downto 0); -- line associated with the instruction leaving the RS
            newline: out std_logic_vector(5 downto 0); -- ROB entry of the newly allocated instruction
            reg_modified: out std_logic_vector(4 downto 0); -- register whose value has to be changed during the commit
            res: out std_logic_vector(PAR-1 downto 0); -- result to be written in reg_modified
            to_be_written: out std_logic; -- if the value produced by the instruction which is currently committing has to be written in the register file
            rob_full: out std_logic; -- if the rob is full (including the incoming instruction in writeback and the instruction that is currently committing)
            deleted_rob_entry: out std_logic_vector(5 downto 0); -- rob entry corresponding to the reg_modified
            is_mispredicted: out std_logic; -- 1 if the branch that we are committing is mispredicted
            pred: out std_logic; -- prediction for the branch is currently committing
            PCN_out: out std_logic_vector(31 downto 0); -- value of the PCN to correct the PC if there is a misprediction
            regb_out: out std_logic_vector(PAR-1 downto 0); -- value of the register b which has to be written in memory during the commit of a store
            to_be_written_in_memory: out std_logic; -- the w_en for the memory of the instruction being committed
            branch_outcome: out std_logic;
            entry_to_delete: out std_logic_vector(5 downto 0);
            WB_instruction_is_head: out std_logic;
            head_ready: out std_logic;
            allocation_not_done: in std_logic;
            ins_leaving_dec: in std_logic;
            rob_entry_leaving_dec: in std_logic_vector(5 downto 0)
        );
    end component;

    component CAM is 
        port(
            R: in std_logic_vector(PAR-1 downto 0);
            W_inval: in std_logic_vector(PAR-1 downto 0);
            ROB_inval: in std_logic_vector(5 downto 0); -- rob entry for the instruction whose memory entry in CAM we want to eliminate
            W_regb: in std_logic_vector(PAR-1 downto 0);
            ROB_write: in std_logic_vector(5 downto 0); -- rob entry for the instruction which accesses an address that we want to write in the CAM
            W_en_inval: in std_logic;
            W_en_regb: in std_logic;
            clk: in std_logic;
            rst: in std_logic; -- for mispredictions
            h_rst: in std_logic; -- for core resets
            M: out std_logic;
            next_inval: out std_logic; -- to determine if at the end of the current cycle there will be an invalidation
            rob_entry: out std_logic_vector(5 downto 0)
        );
    end component;

    component reservation_stations is
        port(
            allocation_done: out std_logic; -- to notify the datapath that the allocation has been done
            instruction_type: in std_logic_vector(2 downto 0); -- same encoding of the ALU, used to determine in which RS the instruction must be inserted
            memory_involved: in std_logic;
            -- busy signals are used to determine in which RS we have to look for available instructions
            add_busy: in std_logic;
            logicals_busy: in std_logic;
            shifter_busy: in std_logic;
            mul_busy: in std_logic;
            div_busy: in std_logic;
            is_terminating: in std_logic; -- 1 if an instruction is terminating
            rob_entry_terminated: in std_logic_vector(5 downto 0); -- rob entry of the instruction in write-back
            commit: in std_logic; -- 1 if a commit is undergoing, because when committing we have to modify the tracking info related to operands
            new_ins: in std_logic; -- 1 if a new instruction has to be allocated (externally we have to check the valid of the F2D and the enable of the D2E to understand if there is a new instruction that will leave the decode in the same cc)
            new_rob_entry: in std_logic_vector(5 downto 0); -- rob entry of the new instruction to be allocated (if new_ins is 1)
            new_op1: in std_logic_vector(5 downto 0); -- op1 for the new instruction
            new_valid_op1: in std_logic_vector(1 downto 0); -- valid for the new instruction,TODO: to be adjusted EXTERNALLY if it is 1 but the corresponding rob entry is being committed in the current cc
            new_op2: in std_logic_vector(5 downto 0);
            new_valid_op2: in std_logic_vector(1 downto 0);
            rob_entry_committed: in std_logic_vector(5 downto 0); -- rob entry of the instruction being committed, the registers where this rob entry appears will be marked as available in the RF
            reg_written: in std_logic_vector(4 downto 0); -- register written as a part of the commit
            ins_is_leaving: out std_logic;
            rob_entry_leaving: out std_logic_vector(5 downto 0); -- rob entry of the instruction that is leaving
            rob_valid_op1: out std_logic_vector(1 downto 0); -- if the op1 for the instruction leaving is valid in the rob(01), otherwise it is valid in the RF (10) or it is invalid(00)
            rob_rf_entry_op1: out std_logic_vector(5 downto 0); -- rob entry or rf entry for op 1 (in case it is a rf entry, only the last 5 bits are used)
            rob_valid_op2: out std_logic_vector(1 downto 0); -- as before, but for op 2
            rob_rf_entry_op2: out std_logic_vector(5 downto 0);
            RS_full: out std_logic; -- 1 if the RS where the incoming instruction should be allocated is full, in this case we have to stall the pipeline
            -- instruction_type_terminated: in std_logic_vector(2 downto 0); -- type of the instruction which is currently terminating
            -- instruction_type_committed: in std_logic_vector(2 downto 0);  -- type of the instruction which is being committed
            rs_full_tc: out std_logic_vector(4 downto 0);
            type_of_ins_leaving: out std_logic_vector(4 downto 0);
    
            clk: in std_logic;
            rst: in std_logic; -- as the ROB
            h_rst: in std_logic
    
        );
    end component;

begin
    -------------- fetch stage + some of the decode/writeback stage
    address_IM <= PC_Curr; -- the instruction fetched in the instruction memory is the one whose address is in the PC right now
    F2D_IR_next <= instruction;
    PC_plus4 <= std_logic_vector(unsigned(PC_curr)+4); -- the memory is byte addressable, so we increase the PC by 4
    F2D_PCN_next <= PC_plus4; -- the value of PC next related to the current instruction, used to compute the destination of branches
    -- instruction memory
    instruction <= data_from_IM;

    -- used to determine if the branch was mispredicted or not, the value is 1 when the branch is being committed and we find out that it has been mispredicted
    is_mispredicted <= is_mispredicted_internal; 

    -- we have to branch when we have a conditional branch whose result is taken or when we have an unconditional branch;
    -- if a branch is predicted correctly then we go on with the execution without forcing a new value in the PC (because the correct one has already been forced during the prediction),
    -- while if it is not, we have to correct the PC depending on the outcome and the prediction;
    -- in particular: 
    --      - if the prediction was untaken and the branch is taken, we write in the PC the result of the branch (destination) (ROB_res), taken from the ROB memory entry of the branch
    --      - if the prediction was taken and the branch is untaken, we have to write in the PC the value of PC next for the branch, because the branch was actually untaken
    PC_computed <= PC_plus4 when is_mispredicted_internal='0' and (F2D_en_int='1' and ins_is_EXIT='0') else PC_curr when is_mispredicted_internal = '0' and not(F2D_en_int='1' and ins_is_EXIT='0') else ROB_res when ROB_pred='0' else ROB_PCN_out;   

    -- ROB_pred is the prediction for the jump instruction in output from the ROB: 1 = prediction taken
    -- ROB_res is the result for the jump instruction
    -- ROB_PCN_out is the address of the next instruction in the ROB


    -- assign to the PC the target address of the branch over which the prediction is being performed 
    -- taken='0' when the jump is predicted not taken OR there is a misprediction: PAY ATTENTION! THE MISPREDICTION IS ALWAYS STRONGER THAN THE PREDICTION FOR THE CURRENT BRANCH
    -- (this is because if we find that a branch has been mispredicted we have to reset the ROB and restart from the correct address independently from the instruction we are checking right now)
    PC_next <= PC_computed when taken='0' else predicted_target;
    -- the BPU can receive as an address the one of the uncorrectly predicted branch (if the corresponding entry has to be updated) or the current value of PC+4
    -- so: when there is a misprediction, the address received is the one of the branch (PCN actually) because the branch entry has to be updated, while in normal condition it receives the PC next related to instruction currently being fetched
    jmp_addr <= PC_plus4 when is_mispredicted_internal='0' else ROB_PCN_out;
    -- BPU port map
    BPU: BTB port map(addr=>jmp_addr(7 downto 0),target=>PC_computed,res=>branch_outcome,jmp_addr=>jmp_addr,rw=>is_mispredicted_internal,clk=>clk,rst=>rst,taken=>taken,predicted_target=>predicted_target);

    -------------- decode stage
    -- first stage: read from RAT, detect commit hazards and, if possible, send the instruction directly to the EXE
    opcode <= F2D_IR_curr(31 downto 26); -- check the value
    func <= F2D_IR_curr(10 downto 0);
    rf_en <= D_rf_en or WB_rf_en;
    -- in case you have an exit you have to stall in the first decode stage
    -- check if the current instruction is an exit, in this case you have to stall the F2D and prevent the instruction from entering ROB/RS
    ins_is_EXIT <= '1' when F2D_IR_curr(10)='1' and RIJ="00" else '0'; -- the exit is an R-type instruction with the msb of the func field set

    -- remove the nop before allocating in the ROB, so you have to act in the first cycle
    -- to determine if the currently decoded instruction is a NOP, so that we can remove it from the pipeline
    ins_is_NOP <= '1' when F2D_IR_curr="00000000000000000000000000000000" else '0';
    DEC2_ins_is_NOP <= '1' when DEC2_IR_curr="00000000000000000000000000000000" else '0';
    -- mux for the WR2 input of the RAT, which depends on the kind of instruction
    WR2_mux_RAT <= F2D_IR_curr(15 downto 11) when dest_sel="00" else F2D_IR_curr(20 downto 16) when dest_sel="01" else "11111";
    
    -- utility signals for RAT and RF ports
    -- you invalidate in the RAT when the instruction in ROB_head is ready to be committed and the instruction writes in the RF
    RAT_inv <= to_be_written and ROB_head_ready;
    -- the overwrite of the RAT content is performed when the instruction leaves the first decode stage
    RAT_WR2_en <= w_reg and F2D_en_int;
    -- the write in the register file is done under the same conditions of the write in the RAT
    RF_WR <= to_be_written and ROB_head_ready;
    -- the allocation in the ROB is performed when it has not been performed before (F2D_en_curr is still 1), the instruction is valid (not NOP neither EXIT) and the rob is not full
    ROB_en_line <= F2D_en_curr_ROB and (not ins_is_NOP) and (not ins_is_EXIT) and not(rob_full_int); -- allocation of a new entry in the ROB is done in the last clock cycle that the instruction spends in decode, so that regb can be allocated in the same cc
    rob_full <= rob_full_int;
    
    next_D2E_is_NOP <= '1' when D2E_IR_next="00000000000000000000000000000000" else '0';
    -- TODO: this port is not used, it should be eliminated
    ROB_WR3_en <= D2E_en and (not next_D2E_is_NOP);

    -- components instantiations
    -- FIX RESET SIGNALS, THEY MUST BE MAPPED TO A SIGNAL THAT IS RAISED WHEN THERE IS A MISPREDICTION
    REORDER_BUFFER: ROB port map(WR1 => ROB_entry_to_delete, inval => ROB_head_ready, WR2 => M2WB_ROB_entry_curr, ins_terminated => M2WB_valid_bit_curr,
                                ins_res => data_to_write, branch_res => M2WB_branchres_curr, RD1 => DEC2_RAT_out1, RD2 => DEC2_RAT_out2, WR_line => F2D_IR_curr,
                                en_line => ROB_en_line, WR_ctrl_word => DEC2_control_next, branch_prediction => F2D_pred_curr, rst => F2D_clr,
                                PCN => F2D_PCN_curr, clk => clk, h_rst => rst, read_line => ROB_head_ready, out1 => ROB_out1, out2 => ROB_out2,
                                out1_valid => ROB_out1_valid, out2_valid => ROB_out2_valid, newline => DEC2_ROB_line_next, entry_to_delete => ROB_entry_to_delete,
                                reg_modified => reg_modified, res => ROB_res, to_be_written => to_be_written, WB_instruction_is_head => WB_instruction_is_head,
                                rob_full => rob_full_int, deleted_rob_entry => deleted_rob_entry, is_mispredicted => is_mispredicted_internal,
                                pred => ROB_pred, PCN_out => ROB_PCN_out, branch_outcome => branch_outcome, regb => D2E_regB_next,
                                regb_out => ROB_regb, to_be_written_in_memory => ROB_mem_w_en, RD3 => E2M_ROB_entry_next, IR_out_exec => ROB_RD3_IR_out,
                                ctrl_out_exec => ROB_RD3_ctrl_out, PCN_out_exec => ROB_RD3_PCN_out, pred_out_exec => ROB_RD3_pred_out,
                                allocation_done => ROB_allocation_done, RD4 => RS_output2_rob_entry_leaving_curr, RD4_out_line => ROB_RD4, RD5 => ROB_in5,
                                RD6 => ROB_in6, out5 => ROB_out5, out6 => ROB_out6, WR3 => D2E_ROB_entry_next, WR3_en => ROB_WR3_en, head_ready => ROB_head_ready,
                                allocation_not_done => F2D_en_curr_ROB, ins_leaving_dec => D2E_en, rob_entry_leaving_dec => D2E_rob_entry_next, out7 => ROB_regb_store,
                                RD7 => CAM_rob_entry_curr);
    -- TODO: ADD CHECKS OVER THE OUTPUTS OF THE RAT TO COMPARE THEM WITH THE ROB ENTRY BEING COMMITTED (in this case you could directly perform a bypass over committed data 
    -- and forward the data that are being committed right now, or maybe you can set artificially the RAT valid signals to be sent to the next stage)
    REGISTER_ALIAS_TABLE: RAT port map(RD1 => F2D_IR_curr(25 downto 21), RD2 => F2D_IR_curr(20 downto 16), WR2 => WR2_mux_RAT,
                                       WR1 => reg_modified, inp => DEC2_ROB_line_next, inv => RAT_inv, WR2_en => RAT_WR2_en, rst => F2D_clr,
                                       clk => clk, h_rst => rst, rob_entry_to_be_deleted => deleted_rob_entry, out1 => RAT_out1, out2 => RAT_out2,
                                       out1_valid => RAT_out1_valid, out2_valid => RAT_out2_valid);
    
    RAT_out1_eq_ROB_committed <= '1' when RAT_out1=deleted_rob_entry else '0';
    RAT_out2_eq_ROB_committed <= '1' when RAT_out2=deleted_rob_entry else '0';
    DEC2_RAT_out1_valid_next <= not ((RAT_out1_eq_ROB_committed and RAT_inv) or RAT_out1_valid); 
    DEC2_RAT_out2_valid_next <= not ((RAT_out2_eq_ROB_committed and RAT_inv) or RAT_out2_valid);
    -- block the first stage if the instruction there is an EXIT
    -- TODO: DO NOT USE ALU_unit, it is represented in one-hot encoding!!
    DEC1_ins_type_from_ALU_OP <= "000" when ALU_unit(0)='1' else
                            "001" when ALU_unit(1)='1' else
                            "010" when ALU_unit(2)='1' else
                            "011" when ALU_unit(3)='1' else
                            "100";
    dec1_to_dec2_en <= (ROB_allocation_done or not (F2D_en_curr_rob) or ins_is_NOP) and (not(RS_full_int)) and not(RS_tc(to_integer(unsigned(DEC1_ins_type_from_ALU_OP))) and RS_new_ins and not (RS_ins_leaving));
    dec1_to_dec2_rst <= (not(dec1_to_dec2_en)) or F2D_clr or rst;
    -- PASS AS FURTHER PARAMETERS THE INSTRUCTION AND THE CONTROL SIGNALS

    RF: register_file port map(CLK => clk, RESET => rst, ENABLE => rf_en,RD1 => rf_rd1_en,RD2 => rf_rd2_en,
                            WR => RF_WR, ADD_WR => reg_modified, ADD_RD1 => RF_in1,
                            ADD_RD2 => RF_in2,DATAIN => ROB_res, OUT1 => RF_out1,
                            OUT2 => RF_out2);

    -- updated busy signals to keep into account the intermediate cycle in the sequence of outputting one ins from the RS
    -- add_busy_with_rs_output2 <= add_busy_int or (RS_output2_type_of_ins_leaving_curr(0) and RS_output2_ins_leaving);
    add_busy_with_rs_output2 <= add_busy_int;
    logicals_busy_with_rs_output2 <= logicals_busy_int or (RS_output2_type_of_ins_leaving_curr(1) and RS_output2_ins_leaving);
    shifter_busy_with_rs_output2 <= shifter_busy_int or (RS_output2_type_of_ins_leaving_curr(2) and RS_output2_ins_leaving);
    mul_busy_with_rs_output2 <= mul_busy_int or (RS_output2_type_of_ins_leaving_curr(3) and RS_output2_ins_leaving);
    div_busy_with_rs_output2 <= div_busy_int or (RS_output2_type_of_ins_leaving_curr(4) and RS_output2_ins_leaving);

    RS: reservation_stations port map(clk => clk, rst => F2D_clr, h_rst => rst, is_terminating => M2WB_valid_bit_curr, rob_entry_terminated => M2WB_rob_entry_curr,
                                      commit => ROB_head_ready, new_ins => RS_new_ins, new_rob_entry => DEC2_ROB_line_curr, new_op1 => op1_rob_or_rf, new_op2 => op2_rob_or_rf,
                                      new_valid_op1 => RS_new_valid_op1, new_valid_op2 => RS_new_valid_op2, rob_entry_committed => ROB_entry_to_delete, reg_written => reg_modified,
                                      ins_is_leaving => RS_ins_leaving, rob_entry_leaving => RS_rob_entry_leaving, rob_valid_op1 => RS_rob_valid_op1,
                                      rob_rf_entry_op1 => RS_rob_rf_entry_op1, rob_valid_op2 => RS_rob_valid_op2, rob_rf_entry_op2 => RS_rob_rf_entry_op2, add_busy => add_busy_with_rs_output2,
                                      logicals_busy => logicals_busy_with_rs_output2, shifter_busy => shifter_busy_with_rs_output2, mul_busy => mul_busy_with_rs_output2, div_busy => div_busy_with_rs_output2,
                                      instruction_type => ins_type_from_ALU_OP, RS_full => RS_full_int, allocation_done => RS_allocation_done, rs_full_tc => RS_tc, type_of_ins_leaving => RS_type_of_ins_leaving,
                                      memory_involved => memory_involved);

    memory_involved <= '1' when DEC2_IR_curr(31 downto 26)="101010" or DEC2_IR_curr(31 downto 26)="010100" else '0'; 
    
    RS_full <= RS_full_int;
    -- registers which store the outputs of the reservation stations during the second cycle in the outputting sequence
    -- the process of outputting a value from the RS has been divided in two because otherwise it would be one of the critical paths
    RS_output2_rob_entry_leaving_next <= RS_rob_entry_leaving;
    RS_output2_rob_valid_op1_next <= "10" when (RS_rob_valid_op1="01" and RS_rob_rf_entry_op1=deleted_rob_entry) or RS_rob_valid_op1="10" else "01"; 
    RS_output2_rob_valid_op2_next <= "10" when (RS_rob_valid_op2="01" and RS_rob_rf_entry_op2=deleted_rob_entry) or RS_rob_valid_op2="10" else "01"; 
    RS_output2_rob_rf_entry_op1_next <= '0'&reg_modified when RS_rob_valid_op1="01" and RS_rob_rf_entry_op1=deleted_rob_entry else RS_rob_rf_entry_op1;
    RS_output2_rob_rf_entry_op2_next <= '0'&reg_modified when RS_rob_valid_op2="01" and RS_rob_rf_entry_op2=deleted_rob_entry else RS_rob_rf_entry_op2;
    RS_output2_type_of_ins_leaving_next <= RS_type_of_ins_leaving;
    RS_output2_en <= RS_ins_leaving;
    RS_output2_rst <= not RS_output2_en or F2D_clr;
    RS_ins_leaving_any_phase <= RS_ins_leaving or RS_output2_ins_leaving;
    -- a signal to tell if an instruction is currently leaving the reservation stations
    ins_is_leaving <= RS_ins_leaving;
    -- TODO: generate the instruction type according to the RS encoding starting from the generic ALU OP produced by the CU
    -- the generation of ins_type should be done over the data coming from the intermediate register in the decode stage, because it is done in the second part
    ins_type_from_ALU_OP <= "000" when DEC2_ALU_unit_int(0)='1' else
                            "001" when DEC2_ALU_unit_int(1)='1' else
                            "010" when DEC2_ALU_unit_int(2)='1' else
                            "011" when DEC2_ALU_unit_int(3)='1' else
                            "100";
    -- drive the D2E_en
    D2E_en <= haz_neg_with_RS;
    -- TODO: change the reference to the intermediate registers
    -- you always try allocating until you actually manage to allocate
    RS_new_ins <= not(DEC2_ins_is_NOP) and ((not dec_ready) or (dec_ready and RS_ins_leaving_any_phase));
    -- you write the register number when the operand is in the register or the instruction which produces it is being committed
    op1_rob_or_rf <= '0'&DEC2_IR_curr(25 downto 21) when DEC2_RAT_out1_valid='0' or (DEC2_RAT_out1_valid='1' and DEC2_RAT_out1=ROB_entry_to_delete and ROB_head_ready='1') else DEC2_RAT_out1;
    op2_rob_or_rf <= '0'&DEC2_IR_curr(20 downto 16) when DEC2_RAT_out2_valid='0' or (DEC2_RAT_out2_valid='1' and DEC2_RAT_out2=ROB_entry_to_delete and ROB_head_ready='1') else DEC2_RAT_out2;
    -- RIJ is used to keep into account the operands required in different kinds of instructions
    RS_new_valid_op1 <= "00" when DEC2_RAT_out1_valid='1' and ROB_out1_valid='0' and (M2WB_valid_bit_curr='0' or M2WB_rob_entry_curr/=DEC2_RAT_out1) and DEC2_RIJ/="10" else -- operands not ready and the instruction which produces them is not terminating
                        "01" when ((DEC2_RAT_out1_valid='1' and ROB_out1_valid='1' and (ROB_head_ready='0' or ROB_entry_to_delete/=DEC2_RAT_out1)) or (DEC2_RAT_out1_valid='1' and ROB_out1_valid='0' and (M2WB_valid_bit_curr='1' or M2WB_rob_entry_curr/=DEC2_RAT_out1))) and DEC2_RIJ/="10" else -- operands ready in the rob and the instruction is not committing
                        "10"; -- operands ready in the RF
    RS_new_valid_op2 <= "00" when DEC2_RAT_out2_valid='1' and ROB_out2_valid='0' and (M2WB_valid_bit_curr='0' or M2WB_rob_entry_curr/=DEC2_RAT_out2) and DEC2_RIJ/="10" and (DEC2_RIJ/="01" or DEC2_rw_dmem='1') else -- operands not ready and the instruction which produces them is not terminating
                        "01" when DEC2_RAT_out2_valid='1' and ((ROB_out2_valid='1' and (ROB_head_ready='0' or ROB_entry_to_delete/=DEC2_RAT_out2)) or (DEC2_RAT_out1_valid='1' and ROB_out1_valid='0' and (M2WB_valid_bit_curr='1' or M2WB_rob_entry_curr/=DEC2_RAT_out1))) and DEC2_RIJ/="10" and (DEC2_RIJ/="01" or DEC2_rw_dmem='1') else -- operands ready in the rob and the instruction is not committing
                        "10"; -- operands ready in the RF
    
    -- bypass logic: if the current writeback instruction is trying to modify a register that the instruction
    -- in decode is trying to read we can bypass the access to the RF and provide to the pipeline register
    -- directly the value that we are writing. This is very useful to avoid stalling the pipeline for one cc
    -- (this would be necessary if we didn't have the bypass, because we would have needed to wait for the 
    -- write operation to terminate before reading)
    -- TODO: DELETE THEM
    -- bypass_detection_RA_before_ROB <= '1' when (WB_w_reg='1' and rf_rd1_en='1' and reg_to_write = F2D_IR_curr(25 downto 21)) else '0'; -- low power
    -- bypass_detection_RB_before_ROB <= '1' when (WB_w_reg='1' and rf_rd2_en='1' and reg_to_write = F2D_IR_curr(20 downto 16)) else '0'; -- low power
    -- -- check if the value that is returned in write-back is the actual one the instruction is waiting for (compare the ROB entry in the RAT with the ROB entry returned)
    -- bypass_detection_RA <= '1' when bypass_detection_RA_before_ROB='1' and RAT_out1=M2WB_rob_entry_curr and RAT_out1_valid='1' else '0';
    -- bypass_detection_RB <= '1' when bypass_detection_RB_before_ROB='1' and RAT_out2=M2WB_rob_entry_curr and RAT_out2_valid='1' else '0';
    
    -- FIRST MUX BETWEEN THE OUTPUT OF THE ROB AND THE ONE OF THE REGISTER FILE
    -- TODO: THESE VALUES MUST BE RETRIEVED FROM THE ROB OR FROM THE RF IN THE SECOND DECODE STAGE
    D2E_regA_next_int <= RF_out1 when DEC2_RAT_out1_valid='0' else ROB_out1;
    D2E_regB_next_int <= RF_out2 when DEC2_RAT_out2_valid='0' else ROB_out2;
    -- SECOND MUX BETWEEN BYPASSED VALUE AND OUTPUT OF THE FIRST ONE
    -- TODO: ELIMINATE BYPASSES!
    -- D2E_regA_next_int <= data_to_write when (bypass_detection_RA='1' and WB_w_reg='1' and rf_rd1_en='1')
    --             else mux_RF_ROB_A; 
    -- D2E_regB_next_int <= data_to_write when (bypass_detection_RB='1' and WB_w_reg='1' and rf_rd2_en='1')
    --             else mux_RF_ROB_B;

    -- if we have an unconditional branch we have to sign extend the whole 26 bits after the opcode,
    -- while in all the other cases we sign-extend the less significant 16 bits
    DEC2_imm_next <= (PAR-1 downto 16 =>F2D_IR_curr(15)) & F2D_IR_curr(15 downto 0) when is_unconditional_branch='0'
                else (PAR-1 downto 26 =>F2D_IR_curr(25)) & F2D_IR_curr(25 downto 0);
    DEC2_IR_next <= F2D_IR_curr;
    DEC2_PCN_next <= F2D_PCN_curr;
    DEC2_pred_next <= F2D_pred_curr; 

    -- TODO: change the references so that the hazards are checked over the second stage of the decode
    -- YOU HAVE TO CHECK THE RAT VALID OUTPUTS COMING FROM THE INTERMEDIATE REGISTER
    -- operands available
    op1_available <= '1' when ROB_out1_valid='1' or DEC2_RAT_out1_valid='0' else '0';
    op2_available <= '1' when ROB_out2_valid='1' or DEC2_RAT_out2_valid='0' else '0';

    operands_available <= op1_available and op2_available;
    -- the exit instruction is never ready when it is in decode 
    operands_available_or_NOP <= '1' when (operands_available='1' or DEC2_ins_is_NOP='1') else '0';
    I_type_mux_out <= operands_available when DEC2_rw_dmem='1' else op1_available;
    -- mux to determine if the operands are available depending on the kind of instruction that we are currently processing
    haz_neg <= operands_available_or_NOP when DEC2_RIJ="00" else I_type_mux_out when DEC2_RIJ="01" else '1';
    -- to consider also instructions leaving the reservation stations (these last ones are prioritized wrt the one ready in decode)
    haz_neg_with_RS <= (dec_ready and not RS_ins_leaving_any_phase and not DEC2_ins_is_NOP) or RS_output2_ins_leaving;

    -- unpacking the value of the ROB_RD4, which is the string in ROB memory associated to the rob entry of the instruction leaving the reservation stations  
    ROB_RD4_instruction <= ROB_RD4(95 downto 64);
    ROB_RD4_control <= ROB_RD4(31 downto 0);
    ROB_RD4_PCN <= ROB_RD4(129 downto 98);
    ROB_RD4_pred <= ROB_RD4(96);
    
    -- next values for the D2E registers in the path starting from the reservation stations
    D2E_imm_next_RS <= (PAR-1 downto 16 =>ROB_RD4_instruction(15)) & ROB_RD4_instruction(15 downto 0) when ROB_RD4_control(15)='0' 
                    else (PAR-1 downto 26 =>ROB_RD4_instruction(25)) & ROB_RD4_instruction(25 downto 0);-- the instruction read from the rob corresponding to the rob entry which is leaving the RS
    D2E_IR_next_RS <= ROB_RD4_instruction;
    D2E_PCN_next_RS <= ROB_RD4_PCN;
    D2E_pred_next_RS <= ROB_RD4_pred;
    D2E_control_next_RS <= ROB_RD4_control;
    -- select the operands which are coming from different places depending on the RS_rob_valid_opX value
    -- TODO: ELIMINATE BYPASSES!
    D2E_regA_next_RS <= ROB_out5 when RS_output2_rob_valid_op1_curr="01" else RF_out1 when RS_output2_rob_valid_op1_curr="10" else data_to_write;
    D2E_regB_next_RS <= ROB_out6 when RS_output2_rob_valid_op2_curr="01" else RF_out2 when RS_output2_rob_valid_op2_curr="10" else data_to_write;
    
    -- multiplex the RF inputs so that the correct value is retrieved when the instruction leaving is the one coming from the reservation stations
    -- TODO: UPDATE THEM TO SELECT EITHER THE VALUE FROM THE INTERMEDIATE DECODE REGISTER OR FROM THE OUTPUT OF THE RS (the sequence of outputting one instruction from the RS should be pipelined in two stages)
    RF_in1 <= DEC2_IR_curr(25 downto 21) when RS_output2_ins_leaving='0' else RS_output2_rob_rf_entry_op1_curr(4 downto 0);
    RF_in2 <= DEC2_IR_curr(20 downto 16) when RS_output2_ins_leaving='0' else RS_output2_rob_rf_entry_op2_curr(4 downto 0); 
    -- the same for ROB inputs
    -- TODO: RECEIVED FROM THE OUTPUT OF THE RS (or from the register after the output, if pipelined)
    ROB_in5 <= RS_output2_rob_rf_entry_op1_curr;
    ROB_in6 <= RS_output2_rob_rf_entry_op2_curr;
    -- TODO: THE NEXT VALUES ARE RECEIVED FROM THE INTERMEDIATE REGISTERS!
    -- next values for the D2E register keeping into account also the reservation stations
    D2E_imm_next <= DEC2_imm_curr when RS_output2_ins_leaving='0' else D2E_imm_next_RS;
    D2E_IR_next <= DEC2_IR_curr when RS_output2_ins_leaving='0' else D2E_IR_next_RS;
    D2E_PCN_next <= DEC2_PCN_curr when RS_output2_ins_leaving='0' else D2E_PCN_next_RS;
    D2E_pred_next <= DEC2_pred_curr when RS_output2_ins_leaving='0' else D2E_pred_next_RS;
    D2E_regA_next <= D2E_regA_next_int when RS_output2_ins_leaving='0' else D2E_regA_next_RS;
    D2E_regB_next <= D2E_regB_next_int when RS_output2_ins_leaving='0' else D2E_regB_next_RS;
    D2E_ROB_entry_next <= DEC2_ROB_line_curr when RS_output2_ins_leaving='0' else RS_output2_rob_entry_leaving_curr;
    D2E_control_next <= DEC2_control_curr when RS_output2_ins_leaving='0' else D2E_control_next_RS;
    
    ------------ execute stage
    -- this check could be anticipated in decode (if it is convenient to do so, check the length of the last decode path)
    ALU_in1 <= D2E_regA_curr when E_OpA_sel='0' else D2E_PCN_curr;  -- alu input1: could be the output of register A or the program counter next (the instruction after the current execution)
    ALU_in2 <= D2E_regB_curr when E_OpB_sel='0' else D2E_imm_curr;  -- alu input2: could be the output of register B or immediate
    -- divType is hardwired to 1, because unsigned division has not yet been implemented
    ALU_E: ALU port map (inp1 => ALU_in1,inp2 => ALU_in2,op => E_ALU_Op,res=>E2M_ALUres_next, rst=>D2E_clr, h_rst=>rst, terminal_cnt => terminal_cnt, clk => clk, divType => '1',
                        ROB_entry_in => D2E_ROB_entry_curr, add_busy => add_busy_int, logicals_busy => logicals_busy_int, shifter_busy => shifter_busy_int, mul_busy => mul_busy_int, div_busy => div_busy_int,
                        ROB_entry_out => E2M_ROB_entry_next, ins_in => D2E_IR_curr, unit => E_ALU_unit, carry_out => ALU_Cout,
                        branchres_out => E2M_branchres_next, beqz_or_bnez => E_beqz_or_bnez, is_branch => E_is_branch, inp_branch => D2E_regA_curr);
    
    -- information about the instruction leaving the EXE is taken from the ROB
    E2M_PCN_next <= ROB_RD3_PCN_out;
    E2M_regB_next <= ROB_RD3_regb_out;
    E2M_IR_next <= ROB_RD3_IR_out;
    E2M_control_next <= ROB_RD3_ctrl_out;
    E2M_pred_next <= ROB_RD3_pred_out;
    E2M_carry_out_next <= ALU_Cout;

    -- busy signals outputs
    add_busy <= add_busy_int;
    logicals_busy <= logicals_busy_int;
    shifter_busy <= shifter_busy_int;
    mul_busy <= mul_busy_int;
    div_busy <= div_busy_int;
    
    ------------ memory stage
    -- comparison circuitry, it works on the ALU result + carry to determine if the operands were equal, the first one was bigger the second one or vice versa
    CMP_sne <= '0' when E2M_ALUres_curr = "00000000000000000000000000000000" else '1';
    CMP_sge <= E2M_carry_out_curr;
    CMP_sle <= not (E2M_carry_out_curr and CMP_sne); -- de Morgan
    CMP_res(31 downto 1) <= (others => '0');
    CMP_res(0) <= CMP_sne when M_ALU_op=SNE_OP else CMP_sge when M_ALU_op=SGE_OP else CMP_sle;
    -- mux to select as output from the ALU either the one coming from E2M or the one outputted from the CMP circuitry
    E2M_ALUres_withCMP <= CMP_res when M_ALU_op=SGE_OP or M_ALU_op=SNE_OP or M_ALU_op=SLE_OP else E2M_ALUres_curr;
    -- multiplexers which produce the output for the M2WB pipeline register
    M2WB_ALUres_next <= E2M_ALUres_withCMP when mux_en_to_WB_registers='0' else ALUres_reg_curr;
    M2WB_control_next <= E2M_control_curr when mux_en_to_WB_registers='0' else control_reg_curr;
    M2WB_PCN_next <= E2M_PCN_curr when mux_en_to_WB_registers='0' else PCN_reg_curr;
    M2WB_IR_next <= E2M_IR_curr when mux_en_to_WB_registers='0' else IR_reg_curr;
    M2WB_branchres_next <= E2M_branchres_curr when mux_en_to_WB_registers='0' else branchres_reg_curr;
    M2WB_rob_entry_next <= E2M_rob_entry_curr when mux_en_to_WB_registers='0' else rob_entry_reg_curr;

    -- signal to determine if ROB_res is equal to ALUres_mux_out, condition under which you have to retrieve data from load registers if a load is ready
    ROB_res_eq_ALUres <= '1' when ROB_res_curr=E2M_ALUres_curr else '0';
    committed_ROB_entry_eq_CAM_ROB_entry <= '1' when deleted_rob_entry_curr=CAM_rob_entry else '0';
    committed_in_first_cycle <= ROB_res_eq_ALUres and committed_ROB_entry_eq_CAM_ROB_entry and CAM_w_en;

    -- mux for the output from the memory
    M2WB_MEMres_next <= data_from_DM when committed_in_first_cycle_curr='1' or CAM_match_curr='0' else ROB_regb_store;

    -- enable for the muxes above:
    mux_en_to_WB_registers <= valid_load_curr;  

    -- the same applies for the regb value, which is used only by store instructions
    M2WB_regb_next <= E2M_regb_curr; 

    -- to determine if the instruction currently in memory is a store
    is_store <= '1' when E2M_IR_curr(31 downto 26)="101010" else '0';
    -- to determine if the instruction currently in memory is a load
    is_load <= '1' when E2M_IR_curr(31 downto 26)="010100" else '0';
    
    -- CAM port map
    CONTENT_ADDRESSABLE_MEMORY: CAM port map(R => E2M_ALUres_curr, W_inval => ROB_res_curr, W_regb => E2M_ALUres_curr, W_en_inval => CAM_w_en,
                                            W_en_regb => is_store, clk => clk, rst => E2M_clr, h_rst => rst, M => CAM_match, ROB_write => E2M_rob_entry_curr,
                                            ROB_inval => deleted_rob_entry_curr, next_inval => CAM_next_inval, rob_entry => CAM_rob_entry);
    
    CAM_w_en <= ROB_mem_w_en_curr;
    -- flip flop and registers process
    process(clk, rst) begin
        if(rst='1') then
            ALUres_reg_curr <= (others =>'0');
            control_reg_curr <= (others =>'0');
            PCN_reg_curr <= (others =>'0');
            IR_reg_curr <= (others =>'0');
            branchres_reg_curr <= '0';
            rob_entry_reg_curr <= (others =>'0');
            valid_load_curr <= '0';
            ROB_res_curr <= (others => '0');
            ROB_mem_w_en_curr <= '0';
            ROB_regb_curr <= (others => '0');
            deleted_rob_entry_curr <= (others => '0');
        elsif(rising_edge(clk)) then
            ROB_res_curr <= ROB_res;
            ROB_mem_w_en_curr <= ROB_mem_w_en;
            deleted_rob_entry_curr <= deleted_rob_entry;
            ROB_regb_curr <= ROB_regb;
            if(E2M_clr='1') then
                valid_load_curr <= '0';
                ROB_res_curr <= (others => '0');
                ROB_mem_w_en_curr <= '0';
                deleted_rob_entry_curr <= (others => '0');
                ROB_regb_curr <= (others => '0');
            else
            -- if there is a load in the intermediate pipeline register, the new instruction coming in E2M goes
            -- in the intermediate register at the next cycle, otherwise it is sent directly to the M2WB. This is 
            -- needed because there must be no situation in which the load and not-load instructions compete for the
            -- M2WB: in this case a signal to the EXE would be needed (to stop further instructions from being sent
            -- to the memory, since one of the two instructions would need to stall), thus increasing the critical path length.
                if(is_load='1' or (valid_load_curr='1' and E2M_valid_bit_curr='1')) then
                    committed_in_first_cycle_curr <= committed_in_first_cycle;
                    CAM_match_curr <= CAM_match;
                    CAM_rob_entry_curr <= CAM_rob_entry;
                    valid_load_curr <= '1';
                    ALUres_reg_curr <= E2M_ALUres_withCMP;
                    control_reg_curr <= E2M_control_curr;
                    PCN_reg_curr <= E2M_PCN_curr;
                    IR_reg_curr <= E2M_IR_curr;
                    branchres_reg_curr <= E2M_branchres_curr;
                    rob_entry_reg_curr <= E2M_rob_entry_curr;
                else
                    -- if there is no other load coming in the E2M register you have to reset the intermediate register for the valid bit
                    valid_load_curr <= '0';
                end if;
            end if;
        end if;
    end process; 

    -- signals to drive the data memory
    address_DM_read <= ALUres_reg_curr;  -- address where you write data
    address_DM_write <= ROB_res_curr;
    data_to_DM <= ROB_regb_curr;    -- data to write in the memory if the instruction is a storemem
    rw_to_DM <= ROB_mem_w_en_curr;

    ------------ write-back stage
    -- to select which data will be written in the RF (data_to_write) depending on the res_sel selector
    -- we can write ALUres (when the instruction doesn't involve the memory), MEMres or PCN (when we have a JAL)
    data_to_write <= M2WB_MEMres_curr when WB_res_sel="00" else M2WB_ALUres_curr;

    -- to select the register where we write data_to_write. If we have a jal we write the result in register 31, which is used to store the return address
    reg_to_write <= M2WB_IR_curr(15 downto 11) when WB_dest_sel="00" else M2WB_IR_curr(20 downto 16) when WB_dest_sel="01" else "11111";

    -- to update the pipeline registers whose enable signals are on
    PIPELINE_REGS: process (clk,rst) begin
        if(rst='1') then
            F2D_en_curr_RS <= '0';
            F2D_en_curr_ROB <= '0';
            F2D_pred_curr <= '0';
            F2D_IR_curr <= (others=>'0');
            F2D_PCN_curr <= (others=>'0');
            D2E_regA_curr <= (others=>'0');
            D2E_regB_curr <= (others=>'0');
            D2E_IR_curr <= (others=>'0');
            D2E_PCN_curr <= (others=>'0');
            D2E_imm_curr <= (others=>'0');
            D2E_control_curr <= (others=>'0'); -- control word
            D2E_pred_curr <= '0';
            D2E_ROB_entry_curr <= (others => '0');
            E2M_ALUres_curr <= (others=>'0');
            E2M_PCN_curr <= (others=>'0'); -- for branches
            E2M_ALUres_curr <= (others=>'0');
            E2M_regB_curr <= (others=>'0');
            E2M_IR_curr <= (others=>'0');
            E2M_control_curr <= (others=>'0'); -- control word
            E2M_branchres_curr <= '0'; -- result of the branch (beqz, bnez)
            E2M_pred_curr <= '0';
            E2M_valid_bit_curr <= '0';
            E2M_carry_out_curr <= '0';
            M2WB_IR_curr <= (others=>'0');
            M2WB_memres_curr <= (others=>'0');
            M2WB_ALUres_curr <= (others=>'0');
            M2WB_PCN_curr <= (others=>'0');
            M2WB_control_curr <= (others=>'0'); -- control word
            M2WB_ROB_entry_curr <= (others =>'0');
            M2WB_valid_bit_curr <= '0';
            M2WB_branchres_curr <= '0';
            M2WB_regb_curr <= (others =>'0');
        elsif (rising_edge(clk)) then
            if(F2D_clr='1') then
                F2D_IR_curr <= (others=>'0');
                F2D_PCN_curr <= (others=>'0');
                F2D_pred_curr <= '0';
                F2D_en_curr_ROB <= '1';
                F2D_en_curr_RS <= '1';
            -- if the current dec instruction is an exit the F2D is stalled indefinitely
            elsif(F2D_en_int='1' and ins_is_EXIT='0') then
                F2D_en_curr_ROB <= '1';
                F2D_en_curr_RS <= '1';
                F2D_IR_curr <= F2D_IR_next;
                F2D_PCN_curr <= F2D_PCN_next;
                F2D_pred_curr <= taken;
            else
                if(RS_allocation_done='1') then
                    F2D_en_curr_RS <= '0';
                end if;
                if(ROB_allocation_done='1') then
                    F2D_en_curr_ROB <= '0';
                end if;
            end if;
            if(dec1_to_dec2_rst='1') then
                DEC2_imm_curr <= (others => '0');
                DEC2_IR_curr <= (others => '0');
                DEC2_PCN_curr <= (others => '0');
                DEC2_pred_curr <= '0';
                DEC2_ROB_line_curr <= (others => '0');
                DEC2_control_curr <= (others => '0');
                DEC2_RAT_out1_valid <= '0';
                DEC2_RAT_out2_valid <= '0';
                DEC2_RAT_out1 <= (others => '0');
                DEC2_RAT_out2 <= (others => '0');
            elsif(dec1_to_dec2_en='1') then
                DEC2_imm_curr <= DEC2_imm_next;
                DEC2_IR_curr <= DEC2_IR_next;
                DEC2_PCN_curr <= DEC2_PCN_next;
                DEC2_pred_curr <= DEC2_pred_next;
                DEC2_ROB_line_curr <= DEC2_ROB_line_next;
                DEC2_control_curr <= DEC2_control_next;
                DEC2_RAT_out1_valid <= RAT_out1_valid;
                DEC2_RAT_out2_valid <= RAT_out2_valid;
                DEC2_RAT_out1 <= RAT_out1;
                DEC2_RAT_out2 <= RAT_out2;
            end if;
            if(RS_output2_rst='1') then
                RS_output2_rob_entry_leaving_curr <= (others => '0');
                RS_output2_rob_valid_op1_curr <= (others => '0'); 
                RS_output2_rob_valid_op2_curr <= (others => '0');
                RS_output2_rob_rf_entry_op1_curr <= (others => '0');
                RS_output2_rob_rf_entry_op2_curr <= (others => '0'); 
                RS_output2_type_of_ins_leaving_curr <= (others => '0');
                -- this is the valid bit of the contents of this register
                RS_output2_ins_leaving <= '0';
            elsif(RS_output2_en='1') then
                RS_output2_rob_entry_leaving_curr <= RS_output2_rob_entry_leaving_next;
                RS_output2_rob_valid_op1_curr <= RS_output2_rob_valid_op1_next; 
                RS_output2_rob_valid_op2_curr <= RS_output2_rob_valid_op2_next;
                RS_output2_rob_rf_entry_op1_curr <= RS_output2_rob_rf_entry_op1_next;
                RS_output2_rob_rf_entry_op2_curr <= RS_output2_rob_rf_entry_op2_next; 
                RS_output2_type_of_ins_leaving_curr <= RS_output2_type_of_ins_leaving_next;
                -- this is the valid bit of the contents of this register
                RS_output2_ins_leaving <= RS_ins_leaving;
            end if;
            -- D2E_rst = D2E_valid_bit_curr and not D2E_en or D2E_clr
            if(D2E_rst='1') then
                D2E_regA_curr <= (others=>'0');
                D2E_regB_curr <= (others=>'0');
                D2E_IR_curr <= (others=>'0');
                D2E_PCN_curr <= (others=>'0');
                D2E_imm_curr <= (others=>'0');
                D2E_control_curr <= (others=>'0'); -- control word
                D2E_pred_curr <= '0';
                D2E_valid_bit_curr <= '0';
                D2E_ROB_entry_curr <= (others =>'0');
            elsif(D2E_en='1') then
                D2E_regA_curr <= D2E_regA_next;
                D2E_regB_curr <= D2E_regB_next;
                D2E_IR_curr <= D2E_IR_next;
                D2E_PCN_curr <= D2E_PCN_next;
                D2E_imm_curr <= D2E_imm_next;
                D2E_control_curr <= D2E_control_next; -- control word
                D2E_pred_curr <= D2E_pred_next;
                D2E_valid_bit_curr <= '1';
                D2E_ROB_entry_curr <= D2E_ROB_entry_next;
            end if;
            -- E2M_rst = E2M_valid_bit_curr and not E2M_en or E2M_clr
            if(E2M_rst='1') then
                E2M_ALUres_curr <= (others=>'0');
                E2M_PCN_curr <= (others=>'0'); -- for branches
                E2M_ALUres_curr <= (others=>'0');
                E2M_regB_curr <= (others=>'0');
                E2M_IR_curr <= (others=>'0');
                E2M_control_curr <= (others=>'0'); -- control word
                E2M_branchres_curr <= '0'; -- result of the branch (beqz, bnez)
                E2M_pred_curr <= '0';
                E2M_valid_bit_curr <= '0';
                E2M_carry_out_curr <= '0';
                E2M_ROB_entry_curr <= (others =>'0');
            -- E2M_en is the terminal count of the ALU
            elsif(E2M_en='1') then
                E2M_ALUres_curr <= E2M_ALUres_next;
                E2M_PCN_curr <= E2M_PCN_next; -- for branches
                E2M_ALUres_curr <= E2M_ALUres_next;
                E2M_regB_curr <= E2M_regB_next;
                E2M_IR_curr <= E2M_IR_next;
                E2M_control_curr <= E2M_control_next; -- control word
                E2M_branchres_curr <= E2M_branchres_next; -- result of the branch (beqz, bnez)
                E2M_pred_curr <= E2M_pred_next;
                E2M_valid_bit_curr <= '1';
                E2M_carry_out_curr <= E2M_carry_out_next;
                E2M_ROB_entry_curr <= E2M_ROB_entry_next;
            end if;
            -- M2WB_rst = M2WB_valid_bit_curr and not M2WB_en or M2WB_clr
            if(M2WB_rst='1') then
                M2WB_IR_curr <= (others=>'0');
                M2WB_memres_curr <= (others=>'0');
                M2WB_ALUres_curr <= (others=>'0');
                M2WB_PCN_curr <= (others=>'0');
                M2WB_control_curr <= (others=>'0'); -- control word
                M2WB_valid_bit_curr <= '0';
                M2WB_ROB_entry_curr <= (others =>'0');
                M2WB_branchres_curr <= '0';
                M2WB_regb_curr <= (others =>'0');
            -- M2WB_en is the valid bit E2M_valid_bit_curr
            elsif(M2WB_en='1') then
                M2WB_IR_curr <= M2WB_IR_next;
                M2WB_memres_curr <= M2WB_memres_next;
                M2WB_ALUres_curr <= M2WB_ALUres_next;
                M2WB_PCN_curr <= M2WB_PCN_next;
                M2WB_control_curr <= M2WB_control_next; -- control word
                M2WB_valid_bit_curr <= '1';
                M2WB_ROB_entry_curr <= M2WB_ROB_entry_next;
                M2WB_branchres_curr <= M2WB_branchres_next;
                M2WB_regb_curr <= M2WB_regb_next;
            end if;
        end if;
    end process;

    -- the F2D is enabled only when the allocation in the ROB can be performed and the RS will be available in the next cycle
    F2D_en_int <= (F2D_en and dec1_to_dec2_en);
    D2E_rst <= (D2E_valid_bit_curr and not D2E_en) or D2E_clr;
    E2M_rst <= (E2M_valid_bit_curr and not E2M_en) or E2M_clr;
    M2WB_rst <= (M2WB_valid_bit_curr and not M2WB_en) or M2WB_clr;
    M2WB_en <= (E2M_valid_bit_curr and not is_load) or valid_load_curr;
    E2M_en <= terminal_cnt;

    -- to update the PC: it has to be updated when the F2D_en is active!
    PC_SEQUENTIAL: process (clk,rst) begin
        if(rst='1') then
            PC_curr <= (others=>'0');
        elsif(rising_edge(clk)) then
            if((F2D_en='1' and ins_is_EXIT='0') or is_mispredicted_internal='1') then
                PC_curr <= PC_next;
            end if;
        end if;
    end process;

    -- you don't need all these assignments, select only the ones that are actually needed for each stage
    -- decode1
    DEC2_control_next(0) <= rw_dmem;
    DEC2_control_next(1) <= OpA_sel;
    DEC2_control_next(2) <= OpB_sel;
    DEC2_control_next(7 downto 3) <= ALU_op;
    DEC2_control_next(8) <= beqz_or_bnez;
    DEC2_control_next(9) <= is_branch;
    DEC2_control_next(11 downto 10) <= res_sel;
    DEC2_control_next(12) <= w_reg;
    DEC2_control_next(14 downto 13) <= dest_sel;
    DEC2_control_next(15) <= is_unconditional_branch;
    DEC2_control_next(17 downto 16) <= RIJ;
    DEC2_control_next(22 downto 18) <= ALU_unit;
    -- decode2
    DEC2_rw_dmem <=DEC2_control_curr(0);
    DEC2_OpA_sel <= DEC2_control_curr(1);
    DEC2_OpB_sel <= DEC2_control_curr(2);
    DEC2_ALU_op <= DEC2_control_curr(7 downto 3);
    DEC2_beqz_or_bnez <= DEC2_control_curr(8);
    DEC2_is_branch <= DEC2_control_curr(9);
    DEC2_res_sel <= DEC2_control_curr(11 downto 10);
    DEC2_w_reg <= DEC2_control_curr(12);
    DEC2_dest_sel <= DEC2_control_curr(14 downto 13);
    DEC2_is_unconditional_branch <= DEC2_control_curr(15);
    DEC2_RIJ <= DEC2_control_curr(17 downto 16);
    DEC2_ALU_unit_int <= DEC2_control_curr(22 downto 18);
    -- DEC2_ALU_unit to the CU, used to perform hazard detection on the second decode stage
    DEC2_ALU_unit <= DEC2_ALU_unit_int;
    -- execute
    E_rw_dmem <=D2E_control_curr(0);
    E_OpA_sel <= D2E_control_curr(1);
    E_OpB_sel <= D2E_control_curr(2);
    E_ALU_op <= D2E_control_curr(7 downto 3);
    E_beqz_or_bnez <= D2E_control_curr(8);
    E_is_branch <= D2E_control_curr(9);
    E_res_sel <= D2E_control_curr(11 downto 10);
    E_w_reg <= D2E_control_curr(12);
    E_dest_sel <= D2E_control_curr(14 downto 13);
    E_is_unconditional_branch <= D2E_control_curr(15);
    E_RIJ <= D2E_control_curr(17 downto 16);
    E_ALU_unit <=D2E_control_curr(22 downto 18);
    -- memory
    M_rw_dmem <=E2M_control_curr(0);
    M_OpA_sel <= E2M_control_curr(1);
    M_OpB_sel <= E2M_control_curr(2);
    M_ALU_op <= E2M_control_curr(7 downto 3);
    M_beqz_or_bnez <= E2M_control_curr(8);
    M_is_branch <= E2M_control_curr(9);
    M_res_sel <= E2M_control_curr(11 downto 10);
    M_w_reg <= E2M_control_curr(12);
    M_dest_sel <= E2M_control_curr(14 downto 13);
    M_is_unconditional_branch <= E2M_control_curr(15);
    M_RIJ <= E2M_control_curr(17 downto 16);
    -- write-back
    WB_rw_dmem <=M2WB_control_curr(0);
    WB_OpA_sel <= M2WB_control_curr(1);
    WB_OpB_sel <= M2WB_control_curr(2);
    WB_ALU_op <= M2WB_control_curr(7 downto 3);
    WB_beqz_or_bnez <= M2WB_control_curr(8);
    WB_is_branch <= M2WB_control_curr(9);
    WB_res_sel <= M2WB_control_curr(11 downto 10);
    WB_w_reg <= M2WB_control_curr(12);
    WB_dest_sel <= M2WB_control_curr(14 downto 13);
    WB_is_unconditional_branch <= M2WB_control_curr(15);
    WB_RIJ <= M2WB_control_curr(17 downto 16);

end dataflow_dp;

configuration CFG_DATAPATH_DATAFLOW of dlx_datapath is
    for dataflow_dp
    end for;
end configuration;