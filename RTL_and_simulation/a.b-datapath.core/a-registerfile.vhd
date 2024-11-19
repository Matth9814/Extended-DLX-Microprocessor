library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;
use WORK.constants.all;
use IEEE.math_real.all;

entity register_file is
 generic(NREG: natural := numReg;
         NBIT: natural := numBitReg);
 port (         CLK: 		IN std_logic;
                RESET: 		IN std_logic;
		ENABLE: 	IN std_logic;
		RD1: 		IN std_logic;						-- sel data out 1
		RD2: 		IN std_logic;						-- sel data out 2
		WR: 		IN std_logic;						-- sel data in
		ADD_WR: 	IN std_logic_vector(natural(ceil(log2(real(NREG))))-1 downto 0);	-- log2 NREGISTER
		ADD_RD1: 	IN std_logic_vector(natural(ceil(log2(real(NREG))))-1 downto 0);	-- log2 NREGISTER
		ADD_RD2: 	IN std_logic_vector(natural(ceil(log2(real(NREG))))-1 downto 0);	-- log2 NREGISTER
		DATAIN: 	IN std_logic_vector(NBIT-1 downto 0);	-- one write port
		OUT1: 		OUT std_logic_vector(NBIT-1 downto 0);	-- two read port
		OUT2: 		OUT std_logic_vector(NBIT-1 downto 0));	-- two read port
end register_file;

architecture BEHAVIORAL of register_file is

  -- suggested structures
  subtype REG_ADDR is natural range 0 to NREG-1; -- using natural type -- subtype defines a smaller set of values of an existing type
  type REG_ARRAY is array(REG_ADDR) of std_logic_vector(NBIT-1 downto 0); -- the type REG_ARRAY is defined as an array of REG_ADDR registers on 64 bits 
  signal REGISTERS : REG_ARRAY;


begin
  
  -- Write process
  Write: process (clk,Reset) 
  begin
    if (Reset='1') then
      for i in REG_ADDR loop
        registers(i) <= (others => '0');
      end loop;
    elsif (rising_edge(clk)) then
      -- Write only when both Wr and En are set to '1'
      if(Wr='1' and Enable='1') then
        registers(to_integer(unsigned(Add_wr))) <= DataIn;
      end if;
    end if;
  end process;
  
  -- Read process
  Read: process(Add_rd1, Add_rd2, Rd1, Rd2, Enable, registers)
  begin
    -- The mux selected signal can change only when
    -- En='1', otherwise it is kept to the last valid value 
    if(Enable='1') then
      if(Rd1='1') then
        out1 <= registers(to_integer(unsigned(Add_rd1)));
      end if;
      if(Rd2='1') then
        out2 <= registers(to_integer(unsigned(Add_rd2)));
      end if;
    end if;
  end process;
end BEHAVIORAL;

configuration CFG_RF_BEH of register_file is
  for BEHAVIORAL
  end for;
end configuration;
