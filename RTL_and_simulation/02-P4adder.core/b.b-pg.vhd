library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.std_logic_unsigned.all;
use work.constants.all;

entity PG is
  port(Pik,Pkj,Gik,Gkj: in std_logic;
       Gij,Pij: out std_logic);
end PG;

architecture BEHAVIORAL of PG is

begin
  
  Gij <= Gik or (Pik and Gkj);
  Pij <= Pik and Pkj;
  
end BEHAVIORAL;

configuration CFG_PG_BEHAVIORAL of PG is
  for BEHAVIORAL
  end for;
end CFG_PG_BEHAVIORAL;
