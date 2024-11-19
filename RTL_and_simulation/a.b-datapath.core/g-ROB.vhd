library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;
use WORK.constants.all;
use IEEE.math_real.all;

-- TODO: PIPELINING THE SINGLE-CYCLE COMMIT WOULD REDUCE THE COMPLEXITY OF THE ROB ITSELF, 
-- BECAUSE IT WOULDN'T BE NECESSARY ANYMORE TO CHECK IF WR1/=WR2, SINCE IT WOULD ALWAYS BE TRUE

entity ROB is
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
end ROB;

architecture ROB_behavioral of ROB is

type StorageT is array (0 to 63) of std_logic_vector(161 downto 0); -- REGB|PCN|BRANCH_RES|PREDICTION|INSTRUCTION|RESULT|CONTROL_WORD
type StateT is array (0 to 63) of std_logic_vector(1 downto 0); -- 00 for free entries, 01 for entries whose instructions are executing, 10 for completed instructions
signal ROB_mem: StorageT;
signal states: StateT;
-- tail pointers: curr_pointer points to the first free position in the ROB
signal curr_pointer: std_logic_vector(5 downto 0); -- pointer to the first free element of the ROB, handled in a circular queue fashion
signal next_pointer: std_logic_vector(5 downto 0);
-- head pointers
signal curr_head: std_logic_vector(5 downto 0);
signal next_head: std_logic_vector(5 downto 0);

signal rw_dmem: std_logic;
signal OpA_sel: std_logic; 
signal OpB_sel: std_logic;
signal ALU_op: std_logic_vector(4 downto 0); 
signal beqz_or_bnez: std_logic;
signal is_branch: std_logic;
signal res_sel: std_logic_vector(1 downto 0);
signal dest_sel: std_logic_vector(1 downto 0);
signal is_unconditional_branch: std_logic;
signal RIJ: std_logic_vector(1 downto 0);

signal res_int: std_logic_vector(PAR-1 downto 0);
signal branch_outcome_int: std_logic;
signal branch_res_int: std_logic;

signal rob_full_int: std_logic;

begin

    -- read statements
    out1 <= ROB_mem(to_integer(unsigned(RD1)))(63 downto 32); -- extract only the result field
    out1_valid <= '1' when states(to_integer(unsigned(RD1)))="10" else '0';
    out2 <= ROB_mem(to_integer(unsigned(RD2)))(63 downto 32); -- extract only the result field
    out2_valid <= '1' when states(to_integer(unsigned(RD2)))="10" else '0';
    RD4_out_line <= ROB_mem(to_integer(unsigned(RD4)));
    out5 <= ROB_mem(to_integer(unsigned(RD5)))(63 downto 32);
    out6 <= ROB_mem(to_integer(unsigned(RD6)))(63 downto 32);
    out7 <= ROB_mem(to_integer(unsigned(RD7)))(161 downto 130); -- the value of regb for the store instruction which produces the value read by the load which is currently in memory
    entry_to_delete <= curr_head;

    -- sequential elements
    process(clk,h_rst) begin
        if(h_rst='1') then
            curr_head <= (others => '0');
            curr_pointer <= (others => '0');
            for i in 0 to 63 loop
                ROB_mem(i) <= (others =>'0');
                states(i) <= (others => '0');
            end loop;
        elsif(rising_edge(clk)) then
            if(rst='1') then
                curr_head <= (others => '0');
                curr_pointer <= (others => '0');
                for i in 0 to 63 loop
                    ROB_mem(i) <= (others =>'0');
                    states(i) <= (others => '0');
                end loop;
            else
                curr_head <= next_head;
                curr_pointer <= next_pointer;
                -- the check over the terminating instruction is performed first, so that if both a termination
                -- and a commit over the same instruction are performed in the same clock cycle there is only
                -- an invalidation of the entry.
                -- check if the result field of an entry has to be filled with the result of the corresponding instruction
                if(ins_terminated='1') then
                    states(to_integer(unsigned(WR2))) <= "10";
                    ROB_mem(to_integer(unsigned(WR2)))(63 downto 32) <= ins_res;
                    ROB_mem(to_integer(unsigned(WR2)))(97) <= branch_res;
                end if;
                -- check if there is an invalidation of an entry to be performed
                if(inval='1') then
                    states(to_integer(unsigned(WR1))) <= "00";
                end if;
                if(ins_leaving_dec='1') then
                    ROB_mem(to_integer(unsigned(rob_entry_leaving_dec)))(161 downto 130) <= regb; -- you have to keep it in the ROB for the store, because as a part of the commit you have to write the value of regb in memory
                end if;
                if(en_line='1') then
                    states(to_integer(unsigned(curr_pointer))) <= "01";
                    ROB_mem(to_integer(unsigned(curr_pointer)))(129 downto 98) <= PCN;
                    ROB_mem(to_integer(unsigned(curr_pointer)))(96) <= branch_prediction;
                    ROB_mem(to_integer(unsigned(curr_pointer)))(95 downto 64) <= WR_line; 
                    ROB_mem(to_integer(unsigned(curr_pointer)))(31 downto 0) <= WR_ctrl_word;
                end if;         
            end if; 
        end if;
    end process;

    -- read data for the instruction leaving the EXE
    IR_out_exec <= ROB_mem(to_integer(unsigned(RD3)))(95 downto 64);
    PCN_out_exec <= ROB_mem(to_integer(unsigned(RD3)))(129 downto 98);
    ctrl_out_exec <= ROB_mem(to_integer(unsigned(RD3)))(31 downto 0);
    pred_out_exec <= ROB_mem(to_integer(unsigned(RD3)))(96);
    allocation_done <= en_line and (not rob_full_int);

    -- next_head and next_pointer update
    -- they are handled as pointers to the entries of a circular buffer
    next_head <= std_logic_vector(unsigned(curr_head)+1) when inval='1' else curr_head;
    next_pointer <= std_logic_vector(unsigned(curr_pointer)+1) when en_line='1' else curr_pointer;
                
    -- when a new instruction is allocated in the rob the value of next_pointer is updated, and the new value is sent to the RAT
    -- PAY ATTENTION: the value of new_line should be the next ROB entry even when the rob entry has not been allocated yet, this is useful when one instruction arrives in dec when the RS is available but the ROB is full
    -- (in this case the allocation in the RS is done first, so the corresponding ROB entry should be already available)
    newline <= curr_pointer when allocation_not_done='1' else std_logic_vector(unsigned(curr_pointer)-1);

    -- register to be updated in the register file and to be unmarked in the RAT
    reg_modified <= ROB_mem(to_integer(unsigned(WR1)))(79 downto 75) when dest_sel="00" else ROB_mem(to_integer(unsigned(WR1)))(84 downto 80) when dest_sel="01" else "11111";
    pred <= ROB_mem(to_integer(unsigned(WR1)))(96);
    PCN_out <= ROB_mem(to_integer(unsigned(WR1)))(129 downto 98);
    deleted_rob_entry <= WR1;

    -- result to be written in register reg_modified
    -- if there is a commit and a write-back on the same rob entry in the same cycle then we have to forward to the output the result provided as input
    res_int <= ROB_mem(to_integer(unsigned(WR1)))(63 downto 32);
    regb_out <= ROB_mem(to_integer(unsigned(WR1)))(161 downto 130);
    branch_res_int <= ROB_mem(to_integer(unsigned(WR1)))(97);
    res <= res_int;

    -- control word unpacking for the instruction which has to be committed in the current cycle
    -- output to tell the memory if the result has to be written at the address ROB_res or not
    to_be_written_in_memory <=ROB_mem(to_integer(unsigned(WR1)))(0) and inval;
    OpA_sel <= ROB_mem(to_integer(unsigned(WR1)))(1);
    OpB_sel <= ROB_mem(to_integer(unsigned(WR1)))(2);
    ALU_op <= ROB_mem(to_integer(unsigned(WR1)))(7 downto 3);
    beqz_or_bnez <= ROB_mem(to_integer(unsigned(WR1)))(8);
    is_branch <= ROB_mem(to_integer(unsigned(WR1)))(9);
    res_sel <= ROB_mem(to_integer(unsigned(WR1)))(11 downto 10);
    -- output to tell the rf is the result has to be written in the register or not
    to_be_written <= ROB_mem(to_integer(unsigned(WR1)))(12) and inval;
    dest_sel <= ROB_mem(to_integer(unsigned(WR1)))(14 downto 13);
    is_unconditional_branch <= ROB_mem(to_integer(unsigned(WR1)))(15);
    RIJ <= ROB_mem(to_integer(unsigned(WR1)))(17 downto 16);

    -- branch logic: if we are committing a branch that is mispredicted then we have to raise the is_mispredicted signal for the CU 
    branch_outcome_int <= '1' when ((branch_res_int='1' and is_branch='1') or is_unconditional_branch='1') else '0';
    is_mispredicted <= (branch_outcome_int xor ROB_mem(to_integer(unsigned(WR1)))(96)) and inval;
    branch_outcome <= branch_outcome_int;

    rob_full_int <= '1' when curr_pointer=curr_head and states(to_integer(unsigned(WR2)))/="00" else '0';
    rob_full <= rob_full_int;

    -- to tell if the instruction coming in WB is the head of the buffer
    WB_instruction_is_head <= '1' when WR2=curr_head and ins_terminated='1' else '0';

    -- if the head is ready to be committed
    head_ready <= '1' when states(to_integer(unsigned(curr_head)))="10" else '0';

end ROB_behavioral;