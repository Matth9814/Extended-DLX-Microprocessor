library IEEE;
use IEEE.std_logic_1164.all; --  libreria IEEE con definizione tipi standard logic
use WORK.constants.all; 	-- libreria WORK user-defined

-- Inverter
entity IV is
	Port (	A:	In	std_logic;		-- Input
			Y:	Out	std_logic);		-- Output
end IV;


architecture BEHAVIORAL of IV is

begin
	Y <= not(A);		-- L'output è il negato dell'input

end BEHAVIORAL;

configuration CFG_IV_BEHAVIORAL of IV is
	for BEHAVIORAL
	end for;
end CFG_IV_BEHAVIORAL;
