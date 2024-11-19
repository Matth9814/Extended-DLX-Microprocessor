library IEEE;
use IEEE.std_logic_1164.all;
use work.constants.all;
use IEEE.math_real.all;
use IEEE.numeric_std.all;

entity SYNCH_UPCOUNTER is -- Synchronous Up Counter
        generic (NBIT: integer := natural(log2(real(numBit)))+1);
	Port(
		COUNT: In std_logic; -- 1/0 Count/Not count
		Q: Out std_logic_vector(NBIT-1 downto 0);
        CLK: In	std_logic;
		RST: In	std_logic -- Synch
		);
end SYNCH_UPCOUNTER;

architecture BEHAVIORAL of SYNCH_UPCOUNTER is
    signal currReg: unsigned(NBIT-1 downto 0);
begin
	process(CLK)
	begin
		if rising_edge(CLK) then
			if RST='1' then
				currReg <= (others =>'0');
			elsif(COUNT='1') then
				currReg <= currReg+1;
			--else currReg <= currReg;
			end if; 
		end if;
	end process;

    Q <= std_logic_vector(currReg);

end BEHAVIORAL;

configuration CFG_SYUPCNT_BEHAVIORAL of SYNCH_UPCOUNTER is
	for BEHAVIORAL
	end for;
end CFG_SYUPCNT_BEHAVIORAL;
