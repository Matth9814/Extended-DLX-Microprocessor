library IEEE;
use IEEE.std_logic_1164.all; --  libreria IEEE con definizione tipi standard logic
use WORK.constants.all; 	 -- libreria WORK user-defined

entity MUX51_GENERIC is
	Generic (NBIT: natural:= numBitMultiplier);  
	Port (	X0:	In	std_logic_vector(NBIT-1 downto 0);
		    X1:	In	std_logic_vector(NBIT-1 downto 0);
		    X2:	In	std_logic_vector(NBIT-1 downto 0);
		    X3:	In	std_logic_vector(NBIT-1 downto 0);
		    X4:	In	std_logic_vector(NBIT-1 downto 0);
		    S:	In	std_logic_vector(2 downto 0);
		    Y:	Out	std_logic_vector(NBIT-1 downto 0));
end MUX51_GENERIC;


architecture BEHAVIORAL of MUX51_GENERIC is
begin
  Y <= X0 when S="000" else
       X1 when S="001" else
       X2 when S="010" else
       X3 when S="011" else
       X4;
end BEHAVIORAL;


configuration CFG_MUX51_BEHAVIORAL of MUX51_GENERIC is
	for BEHAVIORAL
	end for;
end CFG_MUX51_BEHAVIORAL;
