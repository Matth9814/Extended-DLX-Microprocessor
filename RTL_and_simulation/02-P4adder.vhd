library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.std_logic_unsigned.all;
use work.constants.all;

entity P4adder is
	generic(NTOT_P4: natural := numBlocksP4*numBitP4;
			NBLKS_P4: natural := numBlocksP4;
			NBIT_P4: natural := numBitP4);
	port(A,B: in std_logic_vector(NTOT_P4-1 downto 0);
	     Cin: in std_logic;
	     Cout: out std_logic;
	     Sum: out std_logic_vector(NTOT_P4-1 downto 0));
end P4adder;

architecture STRUCTURAL of P4adder is
	component SUM_GENERATOR is
  		generic(NBIT: natural:= numBitP4;
 	                NBLKS: natural:= numBlocksP4);
  		port(A,B: in std_logic_vector((NBIT*NBLKS)-1 downto 0);
       		     Cin: in std_logic_vector(NBLKS-1 downto 0);
       		     Sum: out std_logic_vector((NBIT*NBLKS)-1 downto 0));
	end component SUM_GENERATOR;

	component CARRY_GENERATOR is
  		generic (NBIT: natural := numBitP4;
                NBLKS: natural := numBlocksP4);
  		port(A,B: in std_logic_vector((NBIT*NBLKS)-1 downto 0);
       	     	     Cin: in std_logic;
             	     Cout: out std_logic_vector(NBLKS-1 downto 0));
	end component CARRY_GENERATOR;
	
	-- constant NBLKS: natural := numBlocksP4;
	signal Cout_cg: std_logic_vector(NBLKS_P4-1 downto 0);
	signal Cin_s: std_logic_vector(NBLKS_P4-1 downto 0);
	
begin
	Cin_s <= Cout_cg(NBLKS_P4-2 downto 0) & Cin;
	SG: SUM_GENERATOR generic map (NBIT=>NBIT_P4, NBLKS=>NBLKS_P4) port map(A=>A,B=>B,Cin=>Cin_s,Sum=>Sum);
	CG: CARRY_GENERATOR generic map (NBIT=>NBIT_P4, NBLKS=>NBLKS_P4) port map(A=>A,B=>B,Cin=>Cin,Cout=>Cout_cg);
	Cout <= Cout_cg(NBLKS_P4-1);

end STRUCTURAL;

configuration CFG_P4adder_STRUCTURAL of P4adder is
	for STRUCTURAL
	end for;
end configuration;
