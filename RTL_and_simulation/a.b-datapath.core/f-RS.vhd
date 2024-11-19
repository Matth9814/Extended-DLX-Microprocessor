library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;
use WORK.constants.all;
use IEEE.math_real.all;

-- TODO: SEPARATE THE RESERVATION STATIONS AND SELECT AN INSTRUCTION DEPENDING ON THE BUSY
-- TODO: DEVISE A MECHANISM TO STALL THE DECODE WHEN AN INSTRUCTION CAN'T BE ALLOCATED IN A RESERVATION STATION BECAUSE THIS ONE IS FULL

-- VERY IMPORTANT: instructions from the reservation stations must always have the precedence over instructions
-- arrived in decode during the current clock cycle. This is because there is the risk of starving the instructions
-- in the reservation stations in case of a chain of nops or independent instructions, thus making it impossible
-- to commit anything.

-- ROB ALLOCATION MUST BE DONE IMMEDIATELY, IN THE CLOCK CYCLE WHEN THE INSTRUCTION ARRIVES IN DECODE!
-- this is needed to correctly track the availability of the operands, since if we keep the current solution (updating the
-- rob only when an instruction leaves the decode) we wouldn't be able to define a data dependency between two instructions in this following case:
-- 1) the first ins is unable to leave the decode and is allocated in the RS (and not in the rob)
-- 2) the second ins, which depends on the result of the first, is unable to go on because of the dependency, but there is no
-- rob entry to be written in the RS to track the operand!

-- the control word, the PCN and the pred for the currently leaving instructions are retrieved from the rob
-- thus we need to multiplex the rob inputs and to add another read port in the rob (to read the whole string in memory associated to a certain instruction)

-- when an instruction leaves the reservation station it is also deleted from the buffers

-- since the RS are oversized, there is no need to make the circuitry to overwrite immediately with a new instruction the slot associated to the
-- one that is currently leaving.

-- SPECIAL INPUTS:
-- new_ins: raise it always when there is an instruction ready
-- new_op1, new_valid_op1, new_op2... : select the rob entry when the instruction is in the rob (either valid or unvalid), the register when it is being committed and write 10 in the valid when the operands are valid in the rf
-- IMPORTANT: when an operand is not important it has to be marked with 10, so that it is considered as already valid in the RF.

entity reservation_stations is
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
        rs_full_tc: out std_logic_vector(4 downto 0);
        type_of_ins_leaving: out std_logic_vector(4 downto 0);

        clk: in std_logic;
        rst: in std_logic; -- as the ROB
        h_rst: in std_logic

    );
end reservation_stations;

architecture behavioral of reservation_stations is
    -- first type is for the station related to a single ALU unit 
    type instruction_station_T is array(0 to 15) of std_logic_vector(6 downto 0); -- VALID|ROB_ENTRY
    -- second type is to aggregate stations for different ALU units
    type instruction_stations_T is array(0 to 5) of instruction_station_T;
    type operands_station_T is array(0 to 15) of std_logic_vector(7 downto 0); -- INVALID/VALID_ROB/VALID_RF|ROB/RF
    type operands_stations_T is array(0 to 5) of operands_station_T;
    type array_of_rob_entries is array(0 to 5) of std_logic_vector(5 downto 0);
    type array_of_valid_bits is array(0 to 5) of std_logic_vector(1 downto 0);
    type array_of_indexes is array(0 to 5) of std_logic_vector(3 downto 0);
    -- reservation stations for the different ALU units
    signal instructions_curr: instruction_stations_T;
    signal first_operands_curr: operands_stations_T;
    signal second_operands_curr: operands_stations_T;
    signal instructions_next: instruction_stations_T;
    signal first_operands_next: operands_stations_T;
    signal second_operands_next: operands_stations_T;
    signal instructions_next_real: instruction_stations_T;
    signal busy_array: std_logic_vector(5 downto 0);
    -- determine if the RS are full
    signal single_RS_full : std_logic;
    signal ins_is_leaving_array : std_logic_vector(5 downto 0);
    signal rob_entry_leaving_array : array_of_rob_entries;
    signal rob_valid_op1_array: array_of_valid_bits;
    signal rob_valid_op2_array: array_of_valid_bits;
    signal rob_rf_entry_op1_array: array_of_rob_entries;
    signal rob_rf_entry_op2_array: array_of_rob_entries;
    signal i_array: array_of_indexes;
    signal RS_full_array: std_logic_vector(5 downto 0);
    signal allocation_done_array: std_logic_vector(5 downto 0);
    -- the counters count from 0 to 15, because in the current state we can't fill the reservation stations (we arrive up to 15 elements)
    signal counters_full_curr: array_of_indexes;
    -- enables to count up or down depending on if an instruction is being allocated or is leaving a reservation station
    signal count_up: std_logic_vector(5 downto 0);
    signal count_down: std_logic_vector(5 downto 0);
    signal instruction_type_int: std_logic_vector(2 downto 0);
    type tail_next is array(0 to 5) of std_logic_vector(3 downto 0);
    signal ls_head_curr: std_logic_vector(3 downto 0);
    signal ls_head_next: std_logic_vector(3 downto 0);
    signal ls_tail_curr: std_logic_vector(3 downto 0);
    signal ls_tail_next: tail_next;
begin
    -- instruction type correction for load and store instructions
    instruction_type_int <= "101" when memory_involved = '1' else instruction_type;
    -- busy array concurrent assignments
    busy_array(0) <= add_busy;
    busy_array(1) <= logicals_busy;
    busy_array(2) <= shifter_busy;
    busy_array(3) <= mul_busy;
    busy_array(4) <= div_busy;
    busy_array(5) <= add_busy; -- the sixth reservation station uses the adder exactly as the first
    -- process to syncronously update the memory contents
    process(clk, h_rst) begin
        if(h_rst='1') then
            for i in 0 to 5 loop
                instructions_curr(i) <= (others => (others => '0'));
                first_operands_curr(i) <= (others => (others => '0'));
                second_operands_curr(i) <= (others => (others => '0'));
                ls_head_curr <= (others => '0');
                ls_tail_curr <= (others => '0');
            end loop;
        elsif(rising_edge(clk)) then
            if(rst='1') then
                for i in 0 to 5 loop
                    instructions_curr(i) <= (others => (others => '0'));
                    first_operands_curr(i) <= (others => (others => '0'));
                    second_operands_curr(i) <= (others => (others => '0'));
                    ls_head_curr <= (others => '0');
                    ls_tail_curr <= (others => '0');
                end loop;
            else
                instructions_curr <= instructions_next_real;
                first_operands_curr <= first_operands_next;
                second_operands_curr <= second_operands_next;
                ls_head_curr <= ls_head_next;
                ls_tail_curr <= ls_tail_next(5);
            end if;
        end if;
    end process;

    -- process to drive single_RS_full, to determine if the reservation station related to the instruction to be inserted is full
    process(instructions_curr, instruction_type_int)
        variable single_RS_is_full : std_logic := '1';
    begin
        single_RS_is_full := '1';
        for j in 0 to 15 loop
            single_RS_is_full := single_RS_is_full and instructions_curr(to_integer(unsigned(instruction_type_int)))(j)(6);
        end loop;
        single_RS_full <= single_RS_is_full;
    end process;

    -- counters update
    process(clk,h_rst)
    begin
        if(h_rst='1') then
            for i in 0 to 5 loop
                counters_full_curr(i) <= (others => '0');
            end loop;
        elsif(rising_edge(clk)) then
            if(rst='1') then
                for i in 0 to 5 loop
                    counters_full_curr(i) <= (others => '0');
                end loop;
            else
                for i in 0 to 5 loop
                    -- increase the count
                    if(count_up(i)='1' and count_down(i)='0') then
                        counters_full_curr(i) <= std_logic_vector(unsigned(counters_full_curr(i))+1);
                    end if;
                    -- decrease the count
                    if(count_up(i)='0' and count_down(i)='1') then
                        counters_full_curr(i) <= std_logic_vector(unsigned(counters_full_curr(i))-1);
                    end if;
                end loop;
            end if;
        end if;
    end process;
    terminal_counts: for i in 0 to 4 generate
        process(counters_full_curr) begin
            if(i=0) then
                if(counters_full_curr(i)="1111" or counters_full_curr(5)="1111") then
                    rs_full_tc(i) <= '1';
                else 
                    rs_full_tc(i) <= '0';
                end if;
            else
                if(counters_full_curr(i)="1111") then
                    rs_full_tc(i) <= '1';
                else
                    rs_full_tc(i) <= '0';
                end if;
            end if;
        end process;
    end generate;
    -- combinational processes
    reservation_stations_process: for j in 0 to 5 generate
    begin
        process(instructions_curr(j), first_operands_curr(j), second_operands_curr(j), reg_written,
                commit, rob_entry_committed, new_ins, new_rob_entry, new_op1, new_op2, new_valid_op1,
                new_valid_op2, is_terminating, rob_entry_terminated, busy_array(j), instruction_type_int, single_RS_full) 
            variable found_one: std_logic := '0';
            variable allocated_one: std_logic := '0';
            variable counter_elem: natural := 0;
            variable index: integer := 0;
        begin
            -- prereset the outputs
            count_up(j) <= '0';
            allocation_done_array(j) <= '0';
            ins_is_leaving_array(j) <= '0';
            rob_entry_leaving_array(j) <= (others => '0');
            rob_valid_op1_array(j) <= (others => '0');
            rob_valid_op2_array(j) <= (others => '0');
            rob_rf_entry_op1_array(j) <= (others => '0');
            rob_rf_entry_op2_array(j) <= (others => '0');
            i_array(j) <= (others => '0');
            RS_full_array(j) <= '0';
            
            -- restore the next values to the current ones (for the current reservation station)
            instructions_next(j) <= instructions_curr(j);
            first_operands_next(j) <= first_operands_curr(j);
            second_operands_next(j) <= second_operands_curr(j);
            ls_tail_next(j) <= ls_tail_curr;
            -- find an instruction to be sent as output
            -- if we are considering a normal reservation station
            if (j/=5) then
                for i in 15 downto 0 loop
                    if(instructions_curr(j)(i)(6)='1') then -- if instruction is valid
                        if(first_operands_curr(j)(i)(7 downto 6)/="00" and second_operands_curr(j)(i)(7 downto 6)/="00") then -- operands are ready
                            ins_is_leaving_array(j) <= not busy_array(j);
                            rob_entry_leaving_array(j) <= instructions_curr(j)(i)(5 downto 0);
                            rob_valid_op1_array(j) <= first_operands_curr(j)(i)(7 downto 6);
                            rob_valid_op2_array(j) <= second_operands_curr(j)(i)(7 downto 6);
                            rob_rf_entry_op1_array(j) <= first_operands_curr(j)(i)(5 downto 0);
                            rob_rf_entry_op2_array(j) <= second_operands_curr(j)(i)(5 downto 0);
                            i_array(j) <= std_logic_vector(to_unsigned(i,4));
                        end if;
                    end if;
                end loop;
            else
                -- if we are considering the L/S reservation station we have to fetch in order
                index := to_integer(unsigned(ls_head_curr));
                if(instructions_curr(j)(index)(6)='1') then -- the instruction in the head is valid
                    if(first_operands_curr(j)(index)(7 downto 6)/="00" and second_operands_curr(j)(index)(7 downto 6)/="00") then -- operands are ready
                        ins_is_leaving_array(j) <= not busy_array(j);
                        rob_entry_leaving_array(j) <= instructions_curr(j)(index)(5 downto 0);
                        rob_valid_op1_array(j) <= first_operands_curr(j)(index)(7 downto 6);
                        rob_valid_op2_array(j) <= second_operands_curr(j)(index)(7 downto 6);
                        rob_rf_entry_op1_array(j) <= first_operands_curr(j)(index)(5 downto 0);
                        rob_rf_entry_op2_array(j) <= second_operands_curr(j)(index)(5 downto 0);
                        i_array(j) <= std_logic_vector(to_unsigned(index,4));
                    end if;
                end if;
            end if;

            -- allocation of a new entry if the newcoming instruction has to be stored in a RS
            -- it is possible to parallelize partially by predetermining where to allocate a new instruction,
            -- this would be easy to do by transforming the buffer in a shift register similar to the one in 
            -- the multiplier pipeline, where a new insertion is always done in the head
            allocated_one := '0';
            if(j=to_integer(unsigned(instruction_type_int))) then
                if (j/=5) then
                    -- classic reservation stations for instructions which do not involve memory accesses
                    if(single_RS_full='0') then -- TODO: COULD BE MOVED INSIDE THE FOR?
                        for i in 0 to 15 loop
                            if(instructions_curr(j)(i)(6) = '0' and allocated_one = '0') then
                                instructions_next(j)(i)(5 downto 0) <= new_rob_entry;
                                instructions_next(j)(i)(6) <= new_ins; -- if new_ins is zero nothing gets allocated, because we are not setting the valid bit
                                first_operands_next(j)(i)(5 downto 0) <= new_op1; -- provided correctly from circuitry located outside
                                second_operands_next(j)(i)(5 downto 0) <= new_op2;
                                first_operands_next(j)(i)(7 downto 6) <= new_valid_op1;
                                second_operands_next(j)(i)(7 downto 6) <= new_valid_op2;
                                allocated_one := '1';
                                allocation_done_array(j) <= '1';
                                count_up(j) <= '1';
                            end if;
                        end loop;
                    else
                        -- the required RS is full, raise the RS_full output to notify the hazard to the CU (which will stall the pipeline)
                        RS_full_array(j) <= '1';
                    end if;
                else
                    -- reservation station for L/S instructions
                    index := to_integer(unsigned(ls_tail_curr));
                    if(single_RS_full='0') then
                        if(instructions_curr(j)(index)(6) = '0' and allocated_one = '0' and new_ins = '1') then
                            instructions_next(j)(index)(5 downto 0) <= new_rob_entry;
                            instructions_next(j)(index)(6) <= '1'; -- if new_ins is zero nothing gets allocated, because we are not setting the valid bit
                            first_operands_next(j)(index)(5 downto 0) <= new_op1; -- provided correctly from circuitry located outside
                            second_operands_next(j)(index)(5 downto 0) <= new_op2;
                            first_operands_next(j)(index)(7 downto 6) <= new_valid_op1;
                            second_operands_next(j)(index)(7 downto 6) <= new_valid_op2;
                            allocated_one := '1';
                            allocation_done_array(j) <= '1';
                            count_up(j) <= '1';
                            ls_tail_next(j) <= std_logic_vector(unsigned(ls_tail_curr)+1);
                        end if;
                    else
                        -- the required RS is full, raise the RS_full output to notify the hazard to the CU (which will stall the pipeline)
                        RS_full_array(j) <= '1';
                    end if;   
                end if;
            end if;

            -- update RS instructions based on the currently committed/written back ones
            for i in 0 to 15 loop
                if(instructions_curr(j)(i)(6)='1') then
                    -- OPERAND 1
                    -- the instruction which produces operand 1 is terminating
                    if(first_operands_curr(j)(i)(7 downto 6)="00" and is_terminating='1' and first_operands_curr(j)(i)(5 downto 0)=rob_entry_terminated) then
                        first_operands_next(j)(i)(7 downto 6) <= "01"; -- operand is valid in the rob
                    end if;
                    -- the instruction that produces operand 1 terminates and is committed in the same cc
                    if(first_operands_curr(j)(i)(7 downto 6)="00" and is_terminating='1' and commit='1' and first_operands_curr(j)(i)(5 downto 0)=rob_entry_terminated and first_operands_curr(j)(i)(5 downto 0)=rob_entry_committed) then
                        first_operands_next(j)(i)(7 downto 6) <= "10"; -- operand is valid in the RF
                        first_operands_next(j)(i)(4 downto 0) <= reg_written;
                    end if;
                    -- the instruction that produces operand 1 is committed, while it terminated some cycles before
                    if(first_operands_curr(j)(i)(7 downto 6)="01" and commit='1' and first_operands_curr(j)(i)(5 downto 0)=rob_entry_committed) then
                        first_operands_next(j)(i)(7 downto 6) <= "10"; -- operand is valid in the rob
                        first_operands_next(j)(i)(4 downto 0) <= reg_written;
                    end if;

                    -- OPERAND 2
                    -- the instruction which produces operand 2 is terminating
                    if(second_operands_curr(j)(i)(7 downto 6)="00" and is_terminating='1' and second_operands_curr(j)(i)(5 downto 0)=rob_entry_terminated) then
                        second_operands_next(j)(i)(7 downto 6) <= "01"; -- operand is valid in the rob
                    end if;
                    -- the instruction that produces operand 2 terminates and is committed in the same cc
                    if(second_operands_curr(j)(i)(7 downto 6)="00" and is_terminating='1' and commit='1' and second_operands_curr(j)(i)(5 downto 0)=rob_entry_terminated and second_operands_curr(j)(i)(5 downto 0)=rob_entry_committed) then
                        second_operands_next(j)(i)(7 downto 6) <= "10"; -- operand is valid in the RF
                        second_operands_next(j)(i)(4 downto 0) <= reg_written;
                    end if;
                    -- the instruction that produces operand 2 is committed, while it terminated some cycles before
                    if(second_operands_curr(j)(i)(7 downto 6)="01" and commit='1' and second_operands_curr(j)(i)(5 downto 0)=rob_entry_committed) then
                        second_operands_next(j)(i)(7 downto 6) <= "10"; -- operand is valid in the rob
                        second_operands_next(j)(i)(4 downto 0) <= reg_written;
                    end if;
                end if;
            end loop;
        end process;
    end generate;

    -- process for multiplexing logic: used to determine the instruction to be sent to exec when there are multiple ins available from different RS
    process(ins_is_leaving_array, rob_entry_leaving_array, rob_valid_op1_array, instructions_next,
             rob_valid_op2_array, rob_rf_entry_op1_array, rob_rf_entry_op2_array, i_array, RS_full_array,
             instruction_type_int, allocation_done_array, ls_head_curr) 
        variable output_found : std_logic := '0';
        variable ins_leaving_index : natural := 0;
        variable ins_leaving_one_hot: natural := 0;
        variable ins_leaving_index_actual: natural :=0;
        variable ins_leaving_one_hot_actual: natural := 0;
    begin 
        count_down <= (others =>'0');
        ls_head_next <= ls_head_curr;
        ins_is_leaving <= '0';
        output_found := '0';
        RS_full <= RS_full_array(to_integer(unsigned(instruction_type_int)));
        allocation_done <= allocation_done_array(to_integer(unsigned(instruction_type_int)));
        instructions_next_real <= instructions_next;
        if(ins_is_leaving_array(0)='1') then
            output_found := '1';
            ins_leaving_index := 0;
            ins_leaving_one_hot := 1;
            ins_leaving_index_actual := 0;
            ins_leaving_one_hot_actual := 1;
        elsif(ins_is_leaving_array(1)='1') then
            output_found := '1';
            ins_leaving_index := 1;
            ins_leaving_one_hot := 2;
            ins_leaving_index_actual := 1;
            ins_leaving_one_hot_actual := 2;
        elsif(ins_is_leaving_array(2)='1') then
            output_found := '1';
            ins_leaving_one_hot := 4;
            ins_leaving_index := 2;
            ins_leaving_index_actual := 2;
            ins_leaving_one_hot_actual := 4;
        elsif(ins_is_leaving_array(3)='1') then
            output_found := '1';
            ins_leaving_one_hot := 8;
            ins_leaving_index := 3;
            ins_leaving_index_actual := 3;
            ins_leaving_one_hot_actual := 8;
        elsif(ins_is_leaving_array(4)='1') then
            output_found := '1';
            ins_leaving_one_hot := 16;
            ins_leaving_index := 4;
            ins_leaving_index_actual := 4;
            ins_leaving_one_hot_actual := 16;
        -- the last reservation station is seen from the outside as equivalent to the first one
        elsif(ins_is_leaving_array(5)='1') then
            output_found := '1';
            ins_leaving_one_hot := 32;
            ins_leaving_index := 5;
            ins_leaving_index_actual := 0;
            ins_leaving_one_hot_actual := 1;
        end if; 
        if(output_found = '1') then
            ins_is_leaving <= '1';
            count_down(ins_leaving_index) <= '1';
            type_of_ins_leaving <= std_logic_vector(to_unsigned(ins_leaving_one_hot_actual,5));
            rob_entry_leaving <= rob_entry_leaving_array(ins_leaving_index);
            instructions_next_real(ins_leaving_index)(to_integer(unsigned(i_array(ins_leaving_index))))(6) <= '0';
            rob_valid_op1 <= rob_valid_op1_array(ins_leaving_index);
            rob_valid_op2 <= rob_valid_op2_array(ins_leaving_index);
            rob_rf_entry_op1 <= rob_rf_entry_op1_array(ins_leaving_index);
            rob_rf_entry_op2 <= rob_rf_entry_op2_array(ins_leaving_index);
            if(ins_leaving_index = 5) then
                ls_head_next <= std_logic_vector(unsigned(ls_head_curr)+1);
            end if;
        end if;
    end process;
end behavioral;