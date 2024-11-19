library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.std_logic_unsigned.all;
use work.constants.all;

entity G is
  port(Pik,Gik,Gkj: in std_logic;
       Gij: out std_logic);
end G;

architecture BEHAVIORAL of G is

begin
  
  Gij <= Gik or (Pik and Gkj);
  
end BEHAVIORAL;

configuration CFG_G_BEHAVIORAL of G is
  for BEHAVIORAL
  end for;
end CFG_G_BEHAVIORAL;

