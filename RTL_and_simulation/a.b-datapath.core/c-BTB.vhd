library ieee;
use ieee.std_logic_1164.all;
use IEEE.numeric_std.all;
use WORK.all;
entity BTB is
port(
    addr: in std_logic_vector(7 downto 0); -- LSbs of the address of the instruction whose entry we are considering
    target: in std_logic_vector(31 downto 0); -- target of the branch considered, written when the branch is computed
    jmp_addr: in std_logic_vector(31 downto 0); -- as addr, but it is the complete address
    res: in std_logic; -- result of the branch
    rw: in std_logic; -- rw is 1 if the branch is mispredicted
    clk: in std_logic;
    rst: in std_logic;
    taken: out std_logic; -- 0 if the branch identified by the entry [addr] (and address [jmp_addr]) is predicted untaken or has been mispredicted (when rw='1') 
    predicted_target: out std_logic_vector(31 downto 0) -- the predicted target for the branch at address [jmp_addr]
);
end BTB;
architecture behavioral of BTB is
    -- the buffer stores the address of the jump instruction, the predicted target and a valid bit for the entry
    type StorageT is array(0 to 255) of std_logic_vector(64 downto 0);
    signal mem_buffer: StorageT;
    signal valid: std_logic;
    signal addr_read: std_logic_vector(31 downto 0);
    signal taken_res: std_logic;
begin 
    -- read process
    process (mem_buffer,rw,addr,res) begin
        -- if you are reading the memory, which means that there is no misprediction being notified
        if(rw='0') then
            -- the address of the instruction stored in the entry [addr] of the BTB, it is ALWAYS a branch (because it is written in the BTB when the corresponding branch is found to be taken)
            addr_read <= mem_buffer(to_integer(unsigned(addr)))(31 downto 0);
            -- the target of the aforementioned branch, it is the result of the computation (if branch is taken) or the PC next if untaken
            predicted_target <= mem_buffer(to_integer(unsigned(addr)))(63 downto 32);
            -- valid bit for the corresponding BTB entry
            valid <= mem_buffer(to_integer(unsigned(addr)))(64);
        end if;
    end process;
    -- write process
    process (clk) begin
        if(rising_edge(clk)) then
            if(rst='1') then
                for i in 0 to 255 loop
                    mem_buffer(i)<=(others=>'0');
                end loop;
            elsif(rw='1') then
                if(res='0') then
                    -- reset the valid bit, because the branch is found to be untaken (so the corresponding entry has to be deleted)
                    mem_buffer(to_integer(unsigned(addr)))(64) <= '0';
                else
                    -- update the buffer entry with the target address and the address of the instruction
                    mem_buffer(to_integer(unsigned(addr)))(63 downto 32) <= target;
                    mem_buffer(to_integer(unsigned(addr)))(31 downto 0) <= jmp_addr;
                    mem_buffer(to_integer(unsigned(addr)))(64) <= '1';
                end if;
            end if;
        end if;
    end process;
    -- taken_res is equal to 1 only when the jump is predicted taken, so only if we find in the BTB the same address of the instruction and the entry is valid
    -- this means that when the entry for a branch is valid (if we check the corresponding entry we find the branch already there) then the branch has been taken before, so the future prediction will taken
    taken_res <= '1' when jmp_addr=addr_read and valid='1' else '0';
    -- taken must be always low when rw=1, because the new address to be loaded in the PC is the one produced in the memory stage 
    -- this is a particular case in which we force the taken to be 0 because the fetch circuitry requires it
    taken <= taken_res when rw='0' else '0'; 

end behavioral;
configuration CFG_BTB of BTB is
    for behavioral
    end for;
end configuration;