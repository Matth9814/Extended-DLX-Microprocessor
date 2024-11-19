library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.std_logic_unsigned.all;
use work.constants.all;

entity PG_elem_net is
  port(a,b: in std_logic;
       p,g: out std_logic);
end PG_elem_net;

architecture BEHAVIORAL of PG_elem_net is

begin
  
  p <= a or b; -- it is not the real definition (a xor b), but it is an
               -- equivalent one when it comes to compute the carry
  g <= a and b;
  
end BEHAVIORAL;

configuration CFG_PG_ELEM_NET_BEHAVIORAL of PG_elem_net is
  for BEHAVIORAL
  end for;
end CFG_PG_ELEM_NET_BEHAVIORAL;
