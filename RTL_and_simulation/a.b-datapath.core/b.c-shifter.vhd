library IEEE;
use IEEE.std_logic_1164.all;
use work.constants.all;

entity SHIFTER is
    generic (NBIT: natural := numBit);
    port(R1: in std_logic_vector(NBIT-1 downto 0);  -- Input to be shifted
         R2: in std_logic_vector(NBIT-1 downto 0);  -- Input
         Options: in std_logic_vector(1 downto 0);  -- Left/Right (bit 0), Arithmetical/Logical (bit 1)
         R3: out std_logic_vector(NBIT-1 downto 0)  -- Output
        );
  end SHIFTER;
  
architecture BEHAVIORAL of SHIFTER is

    signal intermediate_output: std_logic_vector(NBIT+7 downto 0);   -- intermediate output on 39 bit

    begin
        -- Three levels:
      process (R1, R2, Options)
        begin
        -- First level: preparing 8 possibile masks, each shifted on 0, 8, 16, 24.
        -- Second level: chose the mask that is the nearest to the shift to be operated using bit 4 and 3 of R2
          if Options(0) = '1' then  -- Shift left, bit 0 di Options = 1
            case (R2(4 downto 3)) is
              when "00" => intermediate_output <= R1 & "00000000"; -- 0
              when "01" => intermediate_output <= R1(23 downto 0) & "0000000000000000"; -- 8
              when "10" => intermediate_output <= R1(15 downto 0) & "000000000000000000000000"; -- 16
              when others => intermediate_output <= R1(7 downto 0) & "00000000000000000000000000000000"; -- 24
            end case;
          else  -- Shift right
            case (R2(4 downto 3)) is
              when "00" => intermediate_output <= "00000000" & R1; -- 0
              when "01" => intermediate_output <= "0000000000000000" & R1(31 downto 8); -- 8
              when "10" => intermediate_output <= "000000000000000000000000" & R1(31 downto 16); -- 16
              when others => intermediate_output <= "00000000000000000000000000000000" & R1(31 downto 24); -- 24
            end case;
          end if;
      end process;

      process (R2, intermediate_output)
        begin
        -- Third level: real shift according to bits 2, 1, 0 of operand R2.
        if Options(0) = '1' then  -- Shift left, bit 0 di Options = 1
          case (R2(2 downto 0)) is
            when "000" => R3 <= intermediate_output(39 downto 8);
            when "001" => R3 <= intermediate_output(38 downto 7);
            when "010" => R3 <= intermediate_output(37 downto 6);
            when "011" => R3 <= intermediate_output(36 downto 5);
            when "100" => R3 <= intermediate_output(35 downto 4);
            when "101" => R3 <= intermediate_output(34 downto 3);
            when "110" => R3 <= intermediate_output(33 downto 2);
            when others => R3 <= intermediate_output(32 downto 1);
          end case;
        else  -- Shift right
          case (R2(2 downto 0)) is
            when "000" => R3 <= intermediate_output(31 downto 0);
            when "001" => R3 <= intermediate_output(32 downto 1);
            when "010" => R3 <= intermediate_output(33 downto 2);
            when "011" => R3 <= intermediate_output(34 downto 3);
            when "100" => R3 <= intermediate_output(35 downto 4);
            when "101" => R3 <= intermediate_output(36 downto 5);
            when "110" => R3 <= intermediate_output(37 downto 6);
            when others => R3 <= intermediate_output(38 downto 7);
          end case;
        end if;
      end process;
    end BEHAVIORAL;

configuration CFG_SHIFTER of SHIFTER is
  for BEHAVIORAL
  end for;
end CFG_SHIFTER;