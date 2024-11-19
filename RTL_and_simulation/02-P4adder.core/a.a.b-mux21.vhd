library IEEE;
use IEEE.std_logic_1164.all; --  libreria IEEE con definizione tipi standard logic
use WORK.constants.all; 	 -- libreria WORK user-defined

entity MUX21_GENERIC is
	Generic (NBIT: natural:= numBitP4);  
	Port (	A:	In	std_logic_vector(NBIT-1 downto 0);
		B:	In	std_logic_vector(NBIT-1 downto 0);
		S:	In	std_logic;
		Y:	Out	std_logic_vector(NBIT-1 downto 0));
end MUX21_GENERIC;


architecture BEHAVIORAL of MUX21_GENERIC is

begin
	pmux: process(A,B,S)
	begin
		if S='1' then	-- If the selection signal is 1 then the ouput is equal to A (after a delay equal to delay_mux)
			Y <= A;
		else
			Y <= B;	-- Else, the output Y is equal to B (after a delay equal to delay_mux)
		end if;

	end process;

end BEHAVIORAL;


architecture STRUCTURAL of MUX21_GENERIC is

	signal Y1: std_logic_vector(NBIT-1 downto 0);
	signal Y2: std_logic_vector(NBIT-1 downto 0);
	signal SB: std_logic;

	component ND2	-- NAND used in the structural description of the MUX
	Port (	A:	In	std_logic;
			B:	In	std_logic;
			Y:	Out	std_logic);
	end component;
	
	component IV	-- INVERTER used in the structural description of the MUX
	Port (	A:	In	std_logic;
			Y:	Out	std_logic);
	end component;

begin
        MUX21: for i in 0 to NBIT-1 generate
  
          UIV : IV
            Port Map ( S, SB);

          UND1 : ND2
            Port Map ( A(i), S, Y1(i));

          UND2 : ND2
            Port Map ( B(i), SB, Y2(i));

          UND3 : ND2
            Port Map ( Y1(i), Y2(i), Y(i));

        end generate;

end STRUCTURAL;

configuration CFG_MUX21_BEHAVIORAL of MUX21_GENERIC is
	for BEHAVIORAL
	end for;
end CFG_MUX21_BEHAVIORAL;

configuration CFG_MUX21_STRUCTURAL of MUX21_GENERIC is
	for STRUCTURAL
		for all : IV
			use configuration WORK.CFG_IV_BEHAVIORAL;
		end for;
		for all : ND2
			use configuration WORK.CFG_ND2_ARCH2;
		end for;
	end for;
end CFG_MUX21_STRUCTURAL;
