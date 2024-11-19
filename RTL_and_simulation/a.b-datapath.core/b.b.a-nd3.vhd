library IEEE;
use IEEE.std_logic_1164.all; 
use WORK.constants.all;

entity ND3 is
	Port (A: in	std_logic;
		B: in std_logic;
        C: in std_logic;
		Y: out std_logic);
end ND3;

-- Both the BEHAVIORAL descriptions use a NAND3 from the std. cell library we are using
-- so they are faster and less area consuming than the implementation using NAND2 and INV
architecture BEHAVIORAL of ND3 is
begin
	Y <= not( A and B and C);
end BEHAVIORAL;

architecture BEHAVIORAL2 of ND3 is
begin
    Y <= not(A nand B) nand C;
end BEHAVIORAL2;

architecture STRUCTURAL of ND3 is
    component ND2 is
        Port(A:	in	std_logic;
            B:	in	std_logic;
            Y:	out	std_logic);
    end component;

    component IV is
        Port (A: in	std_logic;
            Y:  out	std_logic);
    end component;

    signal L0,L0_inv: std_logic;
begin
    -- not(A and B and C) = not(not(not(A and B)) and C)
    NAND0: nd2 port map (A=>A,B=>B,Y=>L0);
    INV0: iv port map (A=>L0,Y=>L0_inv);
    NAND1: nd2 port map (A=>L0_inv,B=>C,Y=>Y);
end STRUCTURAL;

configuration CFG_ND3_BEHAV of ND3 is
	for BEHAVIORAL
	end for;
end CFG_ND3_BEHAV;

configuration CFG_ND3_BEHAV2 of ND3 is
	for BEHAVIORAL2
	end for;
end CFG_ND3_BEHAV2;

configuration CFG_ND3_STRUCTURAL of ND3 is
    for STRUCTURAL
        for NAND0 : nd2
            use configuration work.CFG_ND2_ARCH1;
        end for;
        for INV0 : iv
            use configuration work.CFG_IV_BEHAVIORAL;
        end for;
        for NAND1 : nd2
            use configuration work.CFG_ND2_ARCH1;
        end for;
    end for;
end CFG_ND3_STRUCTURAL;

