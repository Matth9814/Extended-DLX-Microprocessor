library IEEE;
use IEEE.std_logic_1164.all;
use work.constants.all;

-- PIPO + SISO (shift register)
entity LEFT_SHIFTER is
    generic (NBIT: natural := numBit);
    port(
        I: in std_logic_vector(NBIT-1 downto 0);
        Q: out std_logic_vector(NBIT-1 downto 0);
        load: in std_logic_vector(1 downto 0);
        -- 00 SERIAL LOAD
        -- 01 PARALLEL LOAD
        -- 10 MEMORY
        rst: in std_logic; -- Synch
        clk: in std_logic
    );
end LEFT_SHIFTER;

architecture BEHAVIORAL of LEFT_SHIFTER is
    signal currReg, nextReg: std_logic_vector(NBIT-1 downto 0);
begin
    COMB: process (load, currReg, I)
    begin
        case load is
            when "00" => -- Serial load
                -- Shift left and load the LSB input
                nextReg <= currReg(NBIT-2 downto 0) & I(0);
            when "01" => -- Parallel load
                nextReg <= I;
            when others => -- Memory
                nextReg <= currReg;
        end case;
    end process;

    REG: process(clk)
    begin
        if rising_edge(clk) then
            if rst='1' then
                currReg <= (others => '0');
            else
                currReg <= nextReg;
            end if;
        end if;
    end process;

    Q <= currReg;

end BEHAVIORAL;

configuration CFG_LSHIFTER_BEHAVIORAL of LEFT_SHIFTER is
    for BEHAVIORAL
    end for;
end configuration;