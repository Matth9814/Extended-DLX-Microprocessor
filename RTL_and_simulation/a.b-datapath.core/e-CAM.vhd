library ieee;
use ieee.std_logic_1164.all;
use IEEE.numeric_std.all;
use WORK.constants.all;
use WORK.all;

entity CAM is 
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
end CAM;
architecture CAM_behavioral of CAM is

    type StorageT is array(0 to 63) of std_logic_vector(PAR-1 downto 0);
    type StorageROB_T is array(0 to 63) of std_logic_vector(5 downto 0);
    signal valid_bits_next: std_logic_vector(0 to 63);
    signal memory_next: StorageT; 
    signal ROB_entries_next: StorageROB_T;
    signal valid_bits_curr: std_logic_vector(0 to 63);
    signal memory_curr: StorageT; 
    signal ROB_entries_curr: StorageROB_T;

begin
    -- process to update the CAM
    process(clk, h_rst) begin
        if(h_rst='1') then
            for i in 0 to 63 loop
                valid_bits_curr(i) <= '0';
            end loop;
        elsif(rising_edge(clk)) then
            if(rst='1') then
                for i in 0 to 63 loop
                    valid_bits_curr(i) <= '0';
                end loop;
            elsif(W_en_inval='1' or W_en_regb='1') then
                valid_bits_curr <= valid_bits_next;
                memory_curr <= memory_next; 
                ROB_entries_curr <= ROB_entries_next;
            end if;    
        end if;
    end process;

    -- process to assign the next values for memory fields and valid bits
    process(W_inval, memory_curr, valid_bits_curr, ROB_entries_curr, W_en_inval, W_regb, ROB_inval, W_en_regb, ROB_write)
        variable same_address_found: std_logic :='0';
        variable allocation_done: std_logic :='0';
    begin
        same_address_found := '0';
        allocation_done := '0';
        ROB_entries_next <= ROB_entries_curr;
        memory_next <= memory_curr;
        valid_bits_next <= valid_bits_curr;
        if(W_en_inval='1') then
            for i in 0 to 63 loop
                -- you can invalidate only if the instruction which performs the commit is the last one who wrote a value at that address 
                if(valid_bits_curr(i)='1' and W_inval=memory_curr(i) and ROB_inval=ROB_entries_curr(i)) then
                    valid_bits_next(i) <= '0';
                else
                    valid_bits_next(i) <= valid_bits_curr(i);
                end if;
            end loop;
        end if;
        if(W_en_regb='1') then
            for i in 0 to 63 loop
                -- look for another valid entry corresponding to the same memory address
                if(valid_bits_curr(i)='1' and W_regb=memory_curr(i)) then
                    valid_bits_next(i) <= '1';
                    memory_next(i) <= W_regb;
                    ROB_entries_next(i) <= ROB_write;
                    same_address_found := '1';
                else
                    valid_bits_next(i) <= valid_bits_curr(i);
                    memory_next(i) <= memory_curr(i);
                    ROB_entries_next(i) <= ROB_entries_curr(i);
                end if;
            end loop;
            if(same_address_found='0') then
                for i in 0 to 63 loop
                    -- if you have not found another entry already allocated for that address:
                    -- you can allocate in a free slot or in a slot that will be free at the end of the cycle
                    if((valid_bits_curr(i)='0' or (W_inval=memory_curr(i) and W_en_inval='1')) and allocation_done='0') then
                        valid_bits_next(i) <= '1';
                        memory_next(i) <= W_regb;
                        ROB_entries_next(i) <= ROB_write;
                        allocation_done := '1';
                    else
                        valid_bits_next(i) <= valid_bits_curr(i);
                        memory_next(i) <= memory_curr(i);
                        ROB_entries_next(i) <= ROB_entries_curr(i);
                    end if;
                end loop;
            end if;
        end if;
    end process;

    -- process to drive the match output
    process(memory_curr, valid_bits_curr, R, ROB_entries_curr) begin
        M <= '0';
        for i in 0 to 63 loop
            if(valid_bits_curr(i)='1' and memory_curr(i)=R) then
                M <= '1';
                rob_entry <= ROB_entries_curr(i);
            end if;
        end loop;
    end process;

    -- process to drive next_inval
    process(memory_curr, valid_bits_curr, W_en_inval, W_inval) begin
        next_inval <= '0';
        if(W_en_inval='1') then
            for i in 0 to 63 loop
                -- you can invalidate only if the instruction which performs the commit is the last one who wrote a value at that address 
                if(valid_bits_curr(i)='1' and W_inval=memory_curr(i)) then -- do not check for the ROB entry, because the next_inval should be activated also when we have a load that is waiting for an old load
                    next_inval <= '1';
                end if;
            end loop;
        end if;
    end process;

end CAM_behavioral;