library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.std_logic_unsigned.all;
use work.constants.all;

entity encoder is
  port(B: in std_logic_vector(2 downto 0); -- The algorithm's radix is 3
       Sel: out std_logic_vector(2 downto 0));
end encoder;

architecture BEHAVIORAL of encoder is
  begin
    Sel <= "000" when (B="000" or B="111") else -- 0
          "001" when (B="001" or B="010") else  -- +A
          "011" when (B="011") else             -- +2A
          "100" when (B="100") else             -- -2A
          "010";                    -- -A
end BEHAVIORAL;
