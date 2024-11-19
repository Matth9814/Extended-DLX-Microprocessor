library IEEE;
use IEEE.std_logic_1164.all;
use work.constants.all;

entity TBLOGICALS is
end TBLOGICALS;

architecture TEST of TBLOGICALS is

    constant NBIT: integer := 32;
	signal	A1:	std_logic_vector(NBIT-1 downto 0);
	signal	B1:	std_logic_vector(NBIT-1 downto 0);
	signal	SEL0:	std_logic;
	signal	SEL1:	std_logic;
	signal	SEL2:	std_logic;
	signal	SEL3:	std_logic;
	signal	Result:	std_logic_vector(NBIT-1 downto 0);
	
	component LOGICALS
		Generic (NBIT: natural := numBit);
		Port(R1: in std_logic_vector(NBIT-1 downto 0);
			R2: in std_logic_vector(NBIT-1 downto 0);
			S0: in std_logic;
			S1: in std_logic;
			S2: in std_logic;
			S3: in std_logic;
			Res: out std_logic_vector(NBIT-1 downto 0)
			);
		end component;

begin 
		
	DUT: LOGICALS
	Generic Map (NBIT)
	Port Map ( A1, B1, SEL0, SEL1, SEL2, SEL3, Result); 

		A1 <= "01011101001100010110001100100100";
		B1 <= "10011000100100010000110110010010";

		-- Other possible combinations:
		-- A1 <= "10110000000000010000000000000000";
		-- B1 <= "11110000000000010000000000000000";
		-- B1 <= "10000000000001110000000000000000";

		SEL0 <= '0', '1' after 10 ns, '0' after 20 ns, '1' after 30 ns, '0' after 40 ns, '1' after 50 ns;
		SEL1 <= '0', '1' after 10 ns, '1' after 20 ns, '0' after 30 ns, '1' after 40 ns, '0' after 50 ns;
		SEL2 <= '0', '1' after 10 ns, '1' after 20 ns, '0' after 30 ns, '1' after 40 ns, '0' after 50 ns;
		SEL3 <= '1', '0' after 10 ns, '1' after 20 ns, '0' after 30 ns, '0' after 40 ns, '1' after 50 ns;

		-- AND:	00011000000100010000000100000000
		-- NAND:11100111111011101111111011111111
		-- OR:	11011101101100010110111110110110
		-- NOR:	00100010010011101001000001001001
		-- XOR:	11000101101000000110111010110110
		-- XNOR:00111010010111111001000101001001

end TEST;

configuration LOGICALSTEST of TBLOGICALS is
   for TEST
      for DUT: LOGICALS
         use configuration WORK.CFG_LOGICALS_STRUCT; 
      end for;
   end for;
end LOGICALSTEST;

