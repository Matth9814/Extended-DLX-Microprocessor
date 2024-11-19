library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;
use WORK.all;
use WORK.constants.all;

entity DLX is
    port(
        rst: in std_logic;
        clk: in std_logic;

        -- signals between datapath and data memory
        address_DM_read: out std_logic_vector(PAR-1 downto 0);
        address_DM_write: out std_logic_vector(PAR-1 downto 0);
        data_to_DM: out std_logic_vector(PAR-1 downto 0);
        data_from_DM: in std_logic_vector(PAR-1 downto 0); 
        rw_to_DM: out std_logic; 

        -- signals from datapath to instruction memory
        address_IM: out std_logic_vector(PAR-1 downto 0);
        data_from_IM: in std_logic_vector(PAR-1 downto 0)
    );
end DLX;

architecture STRUCTURAL of DLX is
    component dlx_datapath is
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
    end component;

    component CU is
        port(
          clk: in std_logic;
          rst: in std_logic; --asynch
          branch_outcome: in std_logic; -- Outcome Branch predictor
          opcode: in  std_logic_vector(5 downto 0);
          DEC2_ALU_unit: in std_logic_vector(4 downto 0); -- the ALU unit where the instruction in DEC2 will be executed
      
          funct: in std_logic_vector(10 downto 0);
      
          ALU_op: out std_logic_vector(4 downto 0);
          ALU_unit: out std_logic_vector(4 downto 0); -- one hot encoding representation of the ALU unit where the operation will be performed
          OpA_sel: out std_logic;
          OpB_sel: out std_logic;
          beqz_or_bnez: out std_logic; -- TODO: use it in a xor operation
          is_branch: out std_logic; -- Is the comparison for a (conditional) branch?
          is_uncond_branch: out std_logic; -- Unconditional branch signaling
          rw_dmem: out std_logic; 
          res_sel: out std_logic_vector(1 downto 0); -- To select ALU or Memory read data
          w_reg: out std_logic;
          dest_sel: out std_logic_vector(1 downto 0); -- To select the register inside the RF
          -- Pipeline registers enable
          F2D_en: out std_logic;
          F2D_clr: out std_logic;
          D2E_clr: out std_logic;
          E2M_clr: out std_logic;
          M2WB_clr: out std_logic;
          RIJ: out std_logic_vector(1 downto 0); -- to determine the kind of instruction (R,I or J)
          ROB_full: in std_logic; -- set to 1 if the ROB is full (considering also the instruction currently in decode and the one going in writeback)
          haz_neg: in std_logic; -- set to 1 if the operands for the instruction in decode are ready, so there is no need to stall
          RS_full: in std_logic; -- 1 if the RS are full
      
          -- busy signals for the ALU units
          add_busy: in std_logic;
          shifter_busy: in std_logic;
          logicals_busy: in std_logic;
          div_busy: in std_logic;
          mul_busy: in std_logic;
      
          -- the ROB entry to be committed
          dec_ready: out std_logic
          );
    end component;
    
    signal F2D_en:  std_logic;
    signal F2D_clr:  std_logic;
    signal D2E_en:  std_logic;
    signal D2E_clr:  std_logic;
    signal E2M_clr:  std_logic;
    signal M2WB_clr:  std_logic;
    signal rw_dmem:  std_logic; -- to select if a read or a write has to be performed in the dmem
    signal OpA_sel:  std_logic; -- to select the first operand to the ALU
    signal OpB_sel:  std_logic; -- to select the second operand to the ALU
    signal ALU_op:  std_logic_vector(4 downto 0); -- selector for ALU operation
    signal beqz_or_bnez:  std_logic; -- to identify if the branch instruction is a beqz_or_bnez
    signal is_branch:  std_logic; -- 1 if the instruction is a branch
    signal res_sel:  std_logic_vector (1 downto 0); -- to select a result between the output of the ALU and the one of the memory
    signal w_reg:  std_logic; -- 1 if we have to write a result in the RF (write enable for the register file)
    signal dest_sel:  std_logic_vector(1 downto 0); -- to select the destination register for the write
    signal is_unconditional_branch:  std_logic; -- 1 if the branch is unconditional
    signal D_rf_en:  std_logic; -- enable for the register file from the instruction in the decode stage
    signal WB_rf_en:  std_logic; -- enable for the register file from the instruction in the writeback stage
    signal rf_rd1_en:  std_logic; -- enable for the first read port
    signal rf_rd2_en:  std_logic; -- enable for the second read port
    signal RIJ: std_logic_vector(1 downto 0);
    signal opcode:  std_logic_vector(5 downto 0);
    signal func:  std_logic_vector(10 downto 0);
    signal is_mispredicted:  std_logic;
    signal commit: std_logic;
    signal strike_start: std_logic_vector(5 downto 0);
    signal strike_detected: std_logic;
    signal strike_length_not_one: std_logic;
    signal rob_full: std_logic;
    signal haz_neg: std_logic;
    signal add_busy: std_logic;
    signal shifter_busy: std_logic;
    signal logicals_busy: std_logic;
    signal mul_busy: std_logic;
    signal div_busy: std_logic;
    signal rob_entry_to_delete: std_logic_vector(5 downto 0);
    signal dec_ready: std_logic;
    signal rs_full: std_logic;
    signal ALU_unit: std_logic_vector(4 downto 0);
    signal DEC2_ALU_unit: std_logic_vector(4 downto 0);

begin
    DATAPATH: DLX_DATAPATH
	Port Map (
        rst => rst, clk => clk, F2D_en => F2D_en, F2D_clr => F2D_clr, D2E_clr => D2E_clr, E2M_clr => E2M_clr,
        M2WB_clr => M2WB_clr, rw_dmem => rw_dmem, OpA_sel => OpA_sel, OpB_sel => OpB_sel, ALU_op => ALU_op, 
        beqz_or_bnez => beqz_or_bnez, is_branch => is_branch, res_sel => res_sel, w_reg => w_reg, dest_sel => dest_sel, 
        is_unconditional_branch => is_unconditional_branch, D_rf_en => '1', WB_rf_en => '1', rf_rd1_en => '1',
        rf_rd2_en => '1', RIJ => RIJ, opcode => opcode, func => func, is_mispredicted => is_mispredicted,
        address_DM_read => address_DM_read, data_to_DM => data_to_DM, data_from_DM => data_from_DM, rw_to_DM => rw_to_DM, address_IM => address_IM, data_from_IM => data_from_IM,
        rob_full => rob_full, haz_neg => haz_neg, ALU_unit => ALU_unit, DEC2_ALU_unit => DEC2_ALU_unit,
        add_busy => add_busy, shifter_busy => shifter_busy, mul_busy => mul_busy, div_busy => div_busy, logicals_busy => logicals_busy,
        address_DM_write => address_DM_write, dec_ready => dec_ready, rs_full => rs_full
    ); 

    CU_DLX: CU port map(
        clk => clk, rst => rst, branch_outcome => is_mispredicted, opcode => opcode,
        funct => func, ALU_op => ALU_op, OpA_sel => OpA_sel, OpB_sel => OpB_sel, beqz_or_bnez => beqz_or_bnez, is_branch => is_branch, is_uncond_branch => is_unconditional_branch,
        rw_dmem => rw_dmem, res_sel => res_sel, w_reg => w_reg, dest_sel => dest_sel, F2D_en => F2D_en,
        F2D_clr => F2D_clr, D2E_clr => D2E_clr, E2M_clr => E2M_clr, M2WB_clr => M2WB_clr, RIJ => RIJ, ROB_full => rob_full, haz_neg => haz_neg,
        add_busy => add_busy, shifter_busy => shifter_busy, logicals_busy => logicals_busy, mul_busy => mul_busy, div_busy => div_busy,
        dec_ready => dec_ready, rs_full => rs_full, DEC2_ALU_unit => DEC2_ALU_unit, ALU_unit => ALU_unit
    );

end STRUCTURAL;