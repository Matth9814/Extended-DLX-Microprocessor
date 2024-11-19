library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;
use WORK.constants.all;
use IEEE.math_real.all;

-- GENERAL DESCRIPTION OF THE ALU ARCHITECTURE: the ALU is composed by multiple units which are in
-- charge of performing different kinds of instructions: adder for additions and comparisons, shifters
-- for shift operations ... Operations of different kinds can be executed in parallel by the different 
-- units, in order to offer support for out of order execution of the program code. When the instructions
-- complete, they are sent as output from the ALU by a multiplexer which receives the outputs from all the
-- different units. If there are multiple units which are terminating execution in the same clock cycle,
-- only one of the terminating instructions is let pass to the memory stage, while the other ones stall in
-- the execute (they are kept in a buffer). The instruction which is sent to the decode depends on a prio
-- level which is decided by an FSM, and this prio level changes every time one instruction terminates.
-- The various ALU modules are not uniform, since they require a different number of clock cycles to terminate
-- execution: for example the adder terminates in 1cc, the multiplier in 16cc (but it is pipelined)... The ALU
-- contains the logic to drive the signals needed to perform the operations correctly.

entity ALU is 
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
end ALU;

architecture ALU_dataflow of ALU is
    
    component P4adder is
        generic(NTOT_P4: natural := numBlocksP4*numBitP4;
                NBLKS_P4: natural := numBlocksP4;
                NBIT_P4: natural := numBitP4);
        port(A,B: in std_logic_vector(NTOT_P4-1 downto 0);
             Cin: in std_logic;
             Cout: out std_logic;
             Sum: out std_logic_vector(NTOT_P4-1 downto 0));
    end component;
    
    component LOGICALS is
        generic (NBIT: natural := numBit);
        port(R1: in std_logic_vector(NBIT-1 downto 0);
             R2: in std_logic_vector(NBIT-1 downto 0);
             S0: in std_logic;
             S1: in std_logic;
             S2: in std_logic;
             S3: in std_logic;
             Res: out std_logic_vector(NBIT-1 downto 0)
            );
    end component;

    component SHIFTER is
        generic (NBIT: natural := numBit);
        port(R1: in std_logic_vector(NBIT-1 downto 0);  -- Input to be shifted
             R2: in std_logic_vector(NBIT-1 downto 0);  -- Input
             Options: in std_logic_vector(1 downto 0);  -- Left/Right (bit 0), Arithmetical/Logical (bit 1)
             R3: out std_logic_vector(NBIT-1 downto 0)  -- Output
            );
    end component;

    component divider is
        generic(NBIT: natural := numBit;
                STEPBIT: natural := natural(log2(real(numBit)))+1);
                -- The algorithm needs 32 step to iterate over each bit of the reminder +
                -- one additional clock cycle to restore the last reminder and change the last bit of the
                -- quotient if Rn<0
                -- The counter has to go from 0 to 32 so it is on 6 bits
        port(
            Z: in std_logic_vector(NBIT-1 downto 0); -- dividend
            D: in std_logic_vector(NBIT-1 downto 0); -- divisor
            Q: out std_logic_vector(NBIT-1 downto 0); -- quotient
            R: out std_logic_vector(NBIT-1 downto 0); -- reminder
            opType: in std_logic; -- 1/0 Signed/Unsigned
            clk: in std_logic;
            enable: in std_logic; -- Enable ACTIVE HIGH -- also used for registers reset
            OpEnd: out std_logic -- Operation finished
        );
    end component;

    component BOOTHMUL is
        generic (NBIT: natural := 32);
        port(
             A: in std_logic_vector(NBIT-1 downto 0);
             B: in std_logic_vector(NBIT-1 downto 0);
             P: out std_logic_vector(2*NBIT-1 downto 0);
             clk: in std_logic;
             terminal_cnt: out std_logic;
             rst: in std_logic; -- to be used in case of mispredictions, when there is the need to flush the entire pipeline after the decode
             h_rst: in std_logic;
             new_mul: in std_logic; -- a new mul is entering the pipeline (a 0 val means that no new mul is entering)
             mul_to_mem: in std_logic; -- a multiplication is leaving the EXE unit
             mul_busy: out std_logic; -- if 15 or 16 slots of the mul are taken
    
             -- input information related to the instructions passing through the pipeline
             ROB_entry_in: in std_logic_vector(5 downto 0);
    
             -- output information
             ROB_entry_out: out std_logic_vector(5 downto 0)
            );
    end component;

    component FSM_DECODE is
        port(
            -- ready signals 
            add_rd: in std_logic;
            log_rd: in std_logic;
            shifter_rd: in std_logic;
            mul_rd: in std_logic;
            div_rd: in std_logic;
    
            clk: in std_logic;
            rst: in std_logic;
            h_rst: in std_logic;
    
            -- reset signals
            ALU_out_dec: out std_logic_vector(2 downto 0);
            add_rst: out std_logic;
            log_rst: out std_logic;
            shifter_rst: out std_logic;
            mul_rst: out std_logic;
            div_rst: out std_logic;
    
            terminal_cnt: out std_logic
        );
    end component;
    
    signal ALU_inner_inp1: std_logic_vector(PAR-1 downto 0);
    signal ALU_inner_inp2: std_logic_vector(PAR-1 downto 0);
    signal ALU_ADDER_inner_inp1: std_logic_vector(PAR-1 downto 0);
    signal ALU_ADDER_inner_inp2: std_logic_vector(PAR-1 downto 0);  
    signal ADDER_inp1: std_logic_vector(PAR-1 downto 0);
    signal ADDER_inp2: std_logic_vector(PAR-1 downto 0);
    signal ALU_Cout: std_logic;  
    signal ALU_Sum: std_logic_vector(PAR-1 downto 0);
    signal CMP_Res: std_logic_vector(PAR-1 downto 0);
    signal logic_out: std_logic_vector(PAR-1 downto 0);
    signal shifter_res: std_logic_vector(PAR-1 downto 0);

    -- ready and enable signals:
    -- ready: set when there is an instruction which is terminating in the current clock cycle or that has already been executed but is still in the execution buffer
    -- enable signals: used for div and mul, they are set in two different cases:
    --      for the mul: when there is a new valid instruction in the D2E reg, so in the next cc this instruction will enter the mul pipeline
    --      for the div: always high when the division is being performed, is kept high until the terminal count is set
    signal add_rd: std_logic;
    signal log_rd: std_logic;
    signal shifter_rd: std_logic;
    signal cmp_rd: std_logic;
    signal mul_rd: std_logic;
    signal mul_en: std_logic;
    signal div_rd: std_logic;
    signal div_en: std_logic;
    -- terminal counts for multiplier and divider (for the mul it indicates that there is an instruction which is leaving the pipeline)
    signal mul_term: std_logic;
    signal div_term: std_logic;

    signal mul_out: std_logic_vector(2*PAR-1 downto 0);
    signal div_out: std_logic_vector(PAR-1 downto 0);
    signal div_rmd: std_logic_vector(PAR-1 downto 0);
    
    signal shifter_options: std_logic_vector(1 downto 0);
    signal twos_complement_on_second: std_logic;
    signal S0: std_logic;
    signal S1: std_logic;
    signal S2: std_logic;
    signal S3: std_logic;
    signal CMP_sne: std_logic;
    signal CMP_sle: std_logic;
    signal CMP_sge: std_logic;
    -- ready registers for the different units: when they are set there is an instruction which has been stored in the corresponding buffer, waiting for the FSM to let it pass
    -- this registers are set when the result computed by the current instruction cannot be sent directly to the memory, mainly because another module has the priority (decided by the FSM)
    signal rd_reg_add: std_logic;
    signal rd_reg_log: std_logic;
    signal rd_reg_div: std_logic;
    signal rd_reg_shifter: std_logic;
    signal rd_reg_cmp: std_logic;

    -- buffers where ready instructions are stored (1 buffer per unit)
    signal reg_add_curr: std_logic_vector(PAR-1 downto 0);
    signal reg_log_curr: std_logic_vector(PAR-1 downto 0);
    signal reg_div_curr: std_logic_vector(PAR-1 downto 0);
    signal reg_shifter_curr: std_logic_vector(PAR-1 downto 0);
    signal reg_cmp_curr: std_logic_vector(PAR-1 downto 0);

    signal reg_div_next: std_logic_vector(PAR-1 downto 0);

    signal add_ins_curr: std_logic_vector(PAR-1 downto 0);

    -- registers to store instruction ROB entries (the mul already has the buffers inside the pipeline)
    signal add_ROB_entry_curr: std_logic_vector(5 downto 0);
    signal log_ROB_entry_curr: std_logic_vector(5 downto 0);
    signal cmp_ROB_entry_curr: std_logic_vector(5 downto 0);
    signal shifter_ROB_entry_curr: std_logic_vector(5 downto 0);
    signal div_ROB_entry_curr: std_logic_vector(5 downto 0);

    -- for the multiplier these are not registers, they are simply the outputs given by the module
    signal mul_ROB_entry_out: std_logic_vector(5 downto 0);
    
    -- inputs to the mux which selects the ROB entry corresponding to the instruction executed by the module which has the priority
    signal add_ROB_entry_mux_in: std_logic_vector(5 downto 0);
    signal log_ROB_entry_mux_in: std_logic_vector(5 downto 0);
    signal cmp_ROB_entry_mux_in: std_logic_vector(5 downto 0);
    signal shifter_ROB_entry_mux_in: std_logic_vector(5 downto 0);
    signal div_ROB_entry_mux_in: std_logic_vector(5 downto 0);

    -- inputs to the mux which outputs the result of the instruction of the selected unit
    signal add_mux_in: std_logic_vector(PAR-1 downto 0);
    signal log_mux_in: std_logic_vector(PAR-1 downto 0);
    signal cmp_mux_in: std_logic_vector(PAR-1 downto 0);
    signal shifter_mux_in: std_logic_vector(PAR-1 downto 0);
    signal mul_mux_in: std_logic_vector(PAR-1 downto 0);
    signal div_mux_in: std_logic_vector(PAR-1 downto 0);

    -- divider enable flip flop, used to drive the enable high for the whole duration of the division
    signal div_en_ff_next: std_logic;
    signal div_en_ff_curr: std_logic;

    signal mux_sel: std_logic_vector(2 downto 0);

    -- reset signals sent from the FSM, they are used to let pass the instruction in the buffer (and so to reset the rd_reg_X value afterward, because the instruction is no more in the buffer)
    signal FSM_add_rst: std_logic;
    signal FSM_log_rst: std_logic;
    signal FSM_mul_rst: std_logic;
    signal FSM_div_rst: std_logic;
    signal FSM_shifter_rst: std_logic;

    signal add_rd_before_mux: std_logic;
    signal log_rd_before_mux: std_logic;
    signal shifter_rd_before_mux: std_logic;
    signal div_rd_before_mux: std_logic;
    signal ins_is_load: std_logic;
    signal not_load_op_mux_in: std_logic;
    signal load_op_mux_in: std_logic;
    signal branchres_ff_next: std_logic;
    signal branch_evaluation_mux_out: std_logic_vector(PAR-1 downto 0);
    signal branchres_ff_curr: std_logic;
    signal carry_mux_in: std_logic;
    signal reg_carry_curr: std_logic;

begin

    -- these assignments have been kept in this way because it is possible to apply some power optimization
    -- by avoiding to change their values when the ALU is not active
    ALU_inner_inp1 <= inp1;
    ALU_inner_inp2 <= inp2; 

    -- the same as before, since it is possible to power optimize the adder by deactivating it when it is not needed
    ALU_ADDER_inner_inp1 <= ALU_inner_inp1;
    ALU_ADDER_inner_inp2 <= ALU_inner_inp2;

    ADDER_inp1 <= ALU_ADDER_inner_inp1; -- the ADDER receives the first input of the ALU directly
    -- extender logic, the second operand is changed only when we want to perform a subtraction and the ALU is active
    twos_complement_on_second <= '1' when op=SUB_OP or op=SNE_OP or op=SGE_OP or op=SLE_OP else '0';
    ADDER_inp2 <= ALU_ADDER_inner_inp2 xor (PAR-1 downto 0 => twos_complement_on_second);
    ADDER: P4adder generic map(NTOT_P4 => 32, NBLKS_P4 => 8, NBIT_P4 => 4) port map(A => ADDER_inp1,B => ADDER_inp2,Cin => twos_complement_on_second,Cout => ALU_Cout, SUM => ALU_sum);
    
    -- decoding logic for the selection signals of the logicals blocks, they are needed to select the correct minterms corresponding to the operation we are going to perform
    S0 <= '0'; -- always 0 because we don't have operations where the minterm a'b' is included in the result
    S1 <= '1' when op=OR_OP or op=XOR_OP else '0'; -- minterm a'b is included in the result only when we perform XOR and OR
    S2 <= '1' when op=OR_OP or op=XOR_OP else '0'; -- the same as before applies for ab'
    S3 <= '1' when op=OR_OP or op=AND_OP else '0'; -- minterm ab is selected when performing OR and AND

    -- shifter control signals: to determine the type of shift and the direction
    shifter_options(1) <= '0'; -- for now, if an arith shift is implemented then this signal has to be driven by the CU
    shifter_options(0) <= '1' when op=SLL_OP else '0';

    LOGIC: LOGICALS port map(R1 => ALU_inner_inp1, R2 => ALU_inner_inp2, S0 => S0, S1 => S1, S2 => S2, S3 => S3, res => logic_out);
    SHIFT: SHIFTER port map(R1 => ALU_inner_inp1, R2 => ALU_inner_inp2, R3 => shifter_res, options => shifter_options);  
    DIV: DIVIDER port map(Z => ALU_inner_inp1, D => ALU_inner_inp2, Q => div_out, R => div_rmd, clk => clk, enable => div_en, OpEnd => div_term, opType => divType);
    FSM: FSM_DECODE port map(add_rd => add_rd, log_rd => log_rd, shifter_rd => shifter_rd, mul_rd => mul_term, div_rd => div_rd, clk => clk, rst => rst, ALU_out_dec => mux_sel, h_rst=>h_rst,
                             add_rst => FSM_add_rst, log_rst => FSM_log_rst, shifter_rst => FSM_shifter_rst, mul_rst => FSM_mul_rst, div_rst => FSM_div_rst, terminal_cnt => terminal_cnt); 
    MUL: BOOTHMUL port map(A => ALU_inner_inp1, B => ALU_inner_inp2, P => mul_out, new_mul => mul_en, clk => clk, terminal_cnt => mul_term, rst => rst, h_rst => h_rst,
                           mul_to_mem => FSM_mul_rst, mul_busy => mul_busy, ROB_entry_in => ROB_entry_in, ROB_entry_out => mul_ROB_entry_out);

    -- the addition is ready either when there is a new addition coming from the dec (because it completes in the same cc) or when there is a completed addition waiting in the buffer (rd_reg_add='1')
    add_rd <= '1' when (unit(0)='1' or rd_reg_add='1') else '0';
    -- the same applies for logicals and shfiter, since the execution completes in the same cc when it is started
    log_rd <= '1' when unit(1)='1' or rd_reg_log='1' else '0';
    shifter_rd <= '1' when unit(2)='1' or rd_reg_shifter='1' else '0';
    -- the ready signal for the div is set only if there is a division that is terminating right now or there is one that has already terminated which is being stored in a buffer
    div_rd <= '1' when (div_term='1' or rd_reg_div='1') else '0';

    -- enable signal for divider: set when there is a division undergoing (op=DIV_OP is included to take into account also the first cycle, when div_en_ff is not set yet)
    div_en_ff_next <= '1' when (unit(4)='1' or div_en_ff_curr='1') else '0';

    mul_en <= '1' when unit(3)='1' else '0'; -- used as a valid bit for the operation that is entering the mul pipeline
    -- the div_en is set to 0 when the terminal count is set
    div_en <= '1' when (unit(4)='1' or (div_en_ff_curr='1' and div_term='0')) else '0';

    -- When the instruction is not a jump (is_branch=0) the output of the mux is 0x0, else it is the value of the regA:
    branch_evaluation_mux_out <= "00000000000000000000000000000000" when is_branch='0' else inp_branch; 
    -- to decide the outcome of the branch, depending on if the regA is at zero and on the kind of branch 
    branchres_ff_next <= '1' when ((branch_evaluation_mux_out="00000000000000000000000000000000" and beqz_or_bnez='0')      -- if it is a beqz and the mux output is 0, OR if it isa bnez and the mux output is not 0 the jump is taken
                                    or (branch_evaluation_mux_out/="00000000000000000000000000000000" and beqz_or_bnez='1')) -- generalize on PAR bits!
                     else '0';

    -- 2 way muxes to select for each unit the current output to be sent as input to the mux
    add_mux_in <= reg_add_curr when rd_reg_add='1' else ALU_sum;
    carry_mux_in <= reg_carry_curr when rd_reg_add='1' else ALU_Cout;
    add_ROB_entry_mux_in <= add_ROB_entry_curr when rd_reg_add='1' else ROB_entry_in;
    branchres_out <= branchres_ff_curr when rd_reg_add='1' else branchres_ff_next;

    log_mux_in <= reg_log_curr when rd_reg_log='1' else logic_out;
    log_ROB_entry_mux_in <= log_ROB_entry_curr when rd_reg_log='1' else ROB_entry_in;

    shifter_mux_in <= reg_shifter_curr when rd_reg_shifter='1' else shifter_res;
    shifter_ROB_entry_mux_in <= shifter_ROB_entry_curr when rd_reg_shifter='1' else ROB_entry_in;

    div_mux_in <= reg_div_curr when rd_reg_div='1' else div_out(PAR-1 downto 0);
    div_ROB_entry_mux_in <= div_ROB_entry_curr;

    -- output muxes
    res <= add_mux_in when mux_sel="000" else -- ensure proper extension of the second operand and manipulation of the carry
           log_mux_in when mux_sel="001" else
           shifter_mux_in when mux_sel="010" else
           mul_out(31 downto 0) when mux_sel="011" else
           div_mux_in when mux_sel="100" else
           (others => '0');
    
    carry_out <= carry_mux_in;

    ROB_entry_out <= add_ROB_entry_mux_in when mux_sel="000" else -- ensure proper extension of the second operand and manipulation of the carry
                    log_ROB_entry_mux_in when mux_sel="001" else
                    shifter_ROB_entry_mux_in when mux_sel="010" else
                    mul_ROB_entry_out when mux_sel="011" else -- the mul has no mux!
                    div_ROB_entry_mux_in when mux_sel="100" else
                    (others => '0');

    -- busy signals generation
    -- the adder/logicals/shifter is busy when either there is a new operation incoming or there is one waiting in the buffer, and this operation can't leave the exec in the current cycle
    add_busy <= '1' when ((unit(0)='1' or rd_reg_add='1') and FSM_add_rst='0') else '0';
    logicals_busy <= '1' when ((unit(1)='1' or rd_reg_log='1') and FSM_log_rst='0') else '0';
    shifter_busy <= '1' when ((unit(2)='1' or rd_reg_shifter='1') and FSM_shifter_rst='0') else '0';
    -- the divider is busy when a division is undergoing or it terminated and it cannot leave the ALU in the current cc 
    div_busy <= '1' when ((unit(4)='1' or div_en_ff_curr='1' or rd_reg_div='1') and FSM_div_rst='0') else '0';

    -- process to handle sequential elements
    process(clk) begin
        -- add a reset sequence of the registers driven by the h_rst
        if(rising_edge(clk)) then
            if(rst='1') then
                rd_reg_add <= '0';
                rd_reg_log <= '0';
                rd_reg_cmp <= '0';
                rd_reg_shifter <= '0';
                rd_reg_div <= '0';
                div_en_ff_curr <= '0';
            else
                -- flip flop for the enable signal of the divider
                if(div_term='1') then -- when the terminal count is set the div_en_ff must be reset
                    div_en_ff_curr <= '0';
                else
                    div_en_ff_curr <= div_en_ff_next;
                end if;
                -- reset has always the precedence
                if(FSM_add_rst='1') then
                    rd_reg_add <= '0';
                elsif(unit(0)='1') then
                    add_ins_curr <= ins_in;
                    add_ROB_entry_curr <= ROB_entry_in;
                    branchres_ff_curr <= branchres_ff_next;
                    -- if the instruction is a sge,sne or sle you have to take the result produced by the comparison circuit, otherwise you take the one produced by the adder
                    if(op=SGE_OP or op=SNE_OP or op=SLE_OP) then
                        reg_add_curr <= CMP_res;
                    else
                        reg_add_curr <= ALU_sum;
                    end if;
                    reg_carry_curr <= ALU_Cout;
                    rd_reg_add <= '1';
                end if;
                if(FSM_log_rst='1') then
                    rd_reg_log <= '0';
                elsif(unit(1)='1') then
                    log_ROB_entry_curr <= ROB_entry_in;
                    reg_log_curr <= logic_out;
                    rd_reg_log <= '1';
                end if;
                if(FSM_shifter_rst='1') then
                    rd_reg_shifter <= '0';
                elsif(unit(2)='1') then
                    shifter_ROB_entry_curr <= ROB_entry_in;
                    reg_shifter_curr <= CMP_res;
                    rd_reg_shifter <= '1';
                end if;
                if(FSM_div_rst='1') then
                    rd_reg_div <= '0';
                else
                    if(unit(4)='1') then
                        div_ROB_entry_curr <= ROB_entry_in;
                    end if;
                    if(div_term='1') then
                        reg_div_curr <= div_out(PAR-1 downto 0);
                        rd_reg_div <= '1';
                    end if;
                end if;
            end if;
        end if;
    end process;

end ALU_dataflow;

configuration CFG_ALU_DATAFLOW of ALU is
    for ALU_dataflow
    end for;
end configuration;
