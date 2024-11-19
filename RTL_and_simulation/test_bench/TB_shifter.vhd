library IEEE;
use IEEE.std_logic_1164.all;
use work.constants.all;

entity TBSHIFTER is
end TBSHIFTER;

architecture TEST of TBSHIFTER is

    constant NBIT: integer := 32;
    component SHIFTER
        generic (NBIT: natural := numBit);
        port(R1: in std_logic_vector(NBIT-1 downto 0);  -- Input to be shifted
            R2: in std_logic_vector(NBIT-1 downto 0);  -- Input
            Options: in std_logic_vector(1 downto 0);  -- Left/Right (bit 0), Arithmetical/Logical (bit 1)
            R3: out std_logic_vector(NBIT-1 downto 0)  -- Output
            );
    end component;
    
    signal	Register1:	std_logic_vector(NBIT-1 downto 0);
	signal	Register2:	std_logic_vector(NBIT-1 downto 0); -- 32 bit non necessari
	signal	ShifterOptions:	std_logic_vector(1 downto 0);
	signal	RegisterOutput:	std_logic_vector(NBIT-1 downto 0);
	

begin 		
	DUT: SHIFTER
	Generic Map (NBIT)
	Port Map ( Register1, Register2, ShifterOptions, RegisterOutput); 
        Register1 <= "01011101001100010110001100100101";
		-- Register2(4 downto 0) <= "00000", "00001" after 10 ns, "00010" after 20 ns, "00011" after 30 ns, "00100" after 40 ns;
        Register2(4 downto 0) <=
                "00000",
                "00001" after 10 ns,
                "00010" after 20 ns,
                "00011" after 30 ns,
                "00100" after 40 ns,
                "00101" after 50 ns,
                "00110" after 60 ns,
                "00111" after 70 ns,
                "01000" after 80 ns,
                "01001" after 90 ns,
                "01010" after 100 ns,
                "01011" after 110 ns,
                "01100" after 120 ns,
                "01101" after 130 ns,
                "01110" after 140 ns,
                "01111" after 150 ns,
                "10000" after 160 ns,
                "10001" after 170 ns,
                "10010" after 180 ns,
                "10011" after 190 ns,
                "10100" after 200 ns,
                "10101" after 210 ns,
                "10110" after 220 ns,
                "10111" after 230 ns,
                "11000" after 240 ns,
                "11001" after 250 ns,
                "11010" after 260 ns,
                "11011" after 270 ns,
                "11100" after 280 ns,
                "11101" after 290 ns,
                "11110" after 300 ns,
                "11111" after 310 ns,
                "00000" after 340 ns,
                "00001" after 350 ns,
                "00010" after 360 ns,
                "00011" after 370 ns,
                "00100" after 380 ns,
                "00101" after 390 ns,
                "00110" after 400 ns,
                "00111" after 410 ns,
                "01000" after 420 ns,
                "01001" after 430 ns,
                "01010" after 440 ns,
                "01011" after 450 ns,
                "01100" after 460 ns,
                "01101" after 470 ns,
                "01110" after 480 ns,
                "01111" after 490 ns,
                "10000" after 500 ns,
                "10001" after 510 ns,
                "10010" after 520 ns,
                "10011" after 530 ns,
                "10100" after 540 ns,
                "10101" after 550 ns,
                "10110" after 560 ns,
                "10111" after 570 ns,
                "11000" after 580 ns,
                "11001" after 590 ns,
                "11010" after 600 ns,
                "11011" after 610 ns,
                "11100" after 620 ns,
                "11101" after 630 ns,
                "11110" after 640 ns,
                "11111" after 650 ns;
                
        ShifterOptions <= "01", "00" after 330 ns;  -- First shift left, then shift right
end TEST;

configuration SHIFTERTEST of TBSHIFTER is
   for TEST
      for DUT: SHIFTER
         use configuration WORK.CFG_SHIFTER; 
      end for;
   end for;
end SHIFTERTEST;

