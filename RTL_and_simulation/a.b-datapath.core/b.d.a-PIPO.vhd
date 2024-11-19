library IEEE;
use IEEE.std_logic_1164.all;
use work.constants.all;

entity PIPO is -- Parallel In/Out register
        generic (NBIT: integer := numBit);
	Port(D:	In	std_logic_vector(NBIT-1 downto 0);
		CLK:	In	std_logic;
		RST:	In	std_logic; -- Synch
		LOAD: In std_logic; -- 1/0 Load/Memory
		Q:	Out	std_logic_vector(NBIT-1 downto 0));
end PIPO;

architecture BEHAVIORAL of PIPO is
begin
	process(CLK)
	begin
	  	if rising_edge(CLK) then
			if RST='1' then
				Q <= (others =>'0');  
			elsif(LOAD='1') then
				Q <= D;
			end if; 
	  	end if;
	end process;

end BEHAVIORAL;

configuration CFG_PIPO_BEHAVIORAL of PIPO is
	for BEHAVIORAL
	end for;
end CFG_PIPO_BEHAVIORAL;
