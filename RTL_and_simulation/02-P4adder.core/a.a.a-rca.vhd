library ieee; 
use ieee.std_logic_1164.all; 
use ieee.std_logic_unsigned.all;
use work.constants.all;

entity RCA is -- Ripple Carry Adder
	generic (NBIT: natural := numBitP4);
	Port (A:	In	std_logic_vector(NBIT-1 downto 0);
		B:	In	std_logic_vector(NBIT-1 downto 0);
		Ci:	In	std_logic;
		S:	Out	std_logic_vector(NBIT-1 downto 0);
		Co:	Out	std_logic);
end RCA; 

architecture STRUCTURAL of RCA is

  signal STMP : std_logic_vector(NBIT-1 downto 0);
  signal CTMP : std_logic_vector(NBIT downto 0);

  component FA 
  Port ( A:	In	std_logic;
	 B:	In	std_logic;
	 Ci:	In	std_logic;
	 S:	Out	std_logic;
	 Co:	Out	std_logic);
  end component; 

begin

  CTMP(0) <= Ci;           -- RCA carry in
  S <= STMP;               -- Sum in output   
  Co <= CTMP(NBIT);        -- RCA carry out
  
  ADDER1: for I in 1 to NBIT generate
    FAI : FA 
	  Port Map (A(I-1), B(I-1), CTMP(I-1), STMP(I-1), CTMP(I)); 
  end generate;

end STRUCTURAL;


architecture BEHAVIORAL of RCA is

begin

  -- Initial description was: S <= (A+B) after DRCAS
  -- Correct description 
  process(A,B,Ci)
    variable STMP: std_logic_vector(NBIT downto 0);
    variable CTMP: std_logic_vector(NBIT downto 0) := (others => '0');
  begin

    CTMP(0) := Ci;
    STMP := ('0'&A) + ('0'&B) + CTMP;
    S <= STMP(NBIT-1 downto 0);
    Co <= STMP(NBIT);

  end process;
end BEHAVIORAL;

configuration CFG_RCA_STRUCTURAL of RCA is
  for STRUCTURAL 
    for ADDER1
      for all : FA
        use configuration WORK.CFG_FA_BEHAVIORAL;
      end for;
    end for;
  end for;
end CFG_RCA_STRUCTURAL;

configuration CFG_RCA_BEHAVIORAL of RCA is
  for BEHAVIORAL 
  end for;
end CFG_RCA_BEHAVIORAL;
