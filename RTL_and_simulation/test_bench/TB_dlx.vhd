library IEEE;
use IEEE.std_logic_1164.all;
use work.constants.all;
use IEEE.numeric_std.all;

entity TBDLX is
end TBDLX;

architecture TEST of TBDLX is

    component DLX is
        port(
            rst: in std_logic;
            clk: in std_logic;
    
            -- signals between datapath and data memory
            address_DM_read: out std_logic_vector(PAR-1 downto 0);
            address_DM_write: out std_logic_vector(PAR-1 downto 0);
            data_to_DM: out std_logic_vector(PAR-1 downto 0);
            data_from_DM: in std_logic_vector(PAR-1 downto 0); 
            rw_to_DM: out std_logic; 
    
            -- signals from datapath to instruction memory
            address_IM: out std_logic_vector(PAR-1 downto 0);
            data_from_IM: in std_logic_vector(PAR-1 downto 0)
        );
    end component;

    component IRAM is
        generic (
          FILE_PATH : string;
          RAM_DEPTH : integer := 65536;
          I_SIZE : integer := 32);
        port (
          Rst: in std_logic;
          Addr : in  std_logic_vector(I_SIZE - 1 downto 0);
          Dout : out std_logic_vector(I_SIZE - 1 downto 0)
        );
      
    end component;

    signal clk: std_logic;
    signal rst: std_logic;
    -- signals between datapath and data memory
    signal address_DM_write: std_logic_vector(PAR-1 downto 0);
    signal address_DM_read: std_logic_vector(PAR-1 downto 0);
    signal data_to_DM: std_logic_vector(PAR-1 downto 0);
    signal data_from_DM: std_logic_vector(PAR-1 downto 0); 
    signal rw_to_DM: std_logic; 
    -- signals from datapath to instruction memory
    signal address_IM: std_logic_vector(PAR-1 downto 0);
    signal data_from_IM: std_logic_vector(PAR-1 downto 0);

    type StorageT is array (0 to 65535) of std_logic_vector(7 downto 0);
    signal Memory: StorageT;

begin 

	DUT: DLX port map(clk => clk, rst => rst, address_DM_read => address_DM_read, address_DM_write => address_DM_write, data_to_DM => data_to_DM, data_from_DM => data_from_DM, rw_to_DM => rw_to_DM, address_IM => address_IM, data_from_IM => data_from_IM);
    
    process begin
        clk <= '0';
        wait for 5 ns;
        clk <= '1';
        wait for 5 ns;
    end process;

    IM: IRAM generic map (FILE_PATH => "test_bench/bubble_sort/bubble_sort_2.asm.mem") port map(rst => rst, Addr => address_IM, Dout => data_from_IM);

    process begin
        -- asynch reset of the DLX
        wait for 0.1 ns;
        rst <= '1';
        wait for 1 ns;
        rst <= '0';
        wait;

        -- produce a test file with a for loop to test branch prediction
        -- // with two consecutive MUL or DIV instructions to check if the counter is reset properly

        -- testing a complete program like this one: (translate it in machine code)
        -- ADDI R1, R1, 6 -->                          00001000001000010000000000000110 --> x08210006
        -- ADDI R2, R2, 2 -->                          00001000010000100000000000000010 --> x08420002
        -- ADD R3, R1, R2 --> hazard D-E and D-M       00000000001000100001100000000001 --> x00221801
        -- MUL R4, R3, R2 --> hazard + stall           00000000011000100010000000011000 --> x00622018
        -- ADD R4, R4, R1                              00000000100000010010000000000001 --> x00812001
        -- DIV R5, R4, R1 --> stall + hazard           00000000100000010010100000011001 --> x00812819
        -- MUL R6,R5,R0                                00000000101000000011000000011000 --> x00A03018
        -- BEQZ R6, punto1 --> should jump to J        00010100110000000000000000000100 --> x14C00004
        -- ADD R6, R6, R1
        -- punto1:                                     00000000110000010011000000000001 --> x00C13001
        -- J punto2   --> should jump to NOP           00100100000000000000000000000100 --> x24000004
        -- ADD R6, R6, R2                              00000000110000100011000000000001 --> x00C23001
        -- punto2:
        -- ADDI R8,R8,4                                09080004
        -- SW R6,0(R8)                                 10101001000001100000000000000000 --> xa9060000
        -- LW R9,0(R8)                                 01010001000010010000000000000000 --> x51090000
        -- ADDI R9,R9,7                                00001001001010010000000000000111 --> x09290007
        -- NOP                                         00000000000000000000000000000000 --> x00000000

    end process;

    -- RAM PROCESSES
    process(rw_to_DM,address_DM_read,Memory) begin
        data_from_DM(7 downto 0)<=Memory(to_integer(unsigned(address_DM_read(15 downto 0))));
        data_from_DM(15 downto 8)<=Memory((to_integer(unsigned(address_DM_read(15 downto 0)))+1) mod 65536);
        data_from_DM(23 downto 16)<=Memory((to_integer(unsigned(address_DM_read(15 downto 0)))+2) mod 65536);
        data_from_DM(31 downto 24)<=Memory((to_integer(unsigned(address_DM_read(15 downto 0)))+3) mod 65536);
	end process;

    -- add a reset signal to clear the contents before the actual execution of the program
	process(clk) begin
		if(rising_edge(clk) and rw_to_DM='1') then
			Memory(to_integer(unsigned(address_DM_write(15 downto 0))))<=data_to_DM(7 downto 0);
			Memory((to_integer(unsigned(address_DM_write(15 downto 0)))+1) mod 65536)<=data_to_DM(15 downto 8);
			Memory((to_integer(unsigned(address_DM_write(15 downto 0)))+2) mod 65536)<=data_to_DM(23 downto 16);
			Memory((to_integer(unsigned(address_DM_write(15 downto 0)))+3) mod 65536)<=data_to_DM(31 downto 24);
		end if;
	end process;

    
end TEST;

configuration DLXTEST of TBDLX is
   for TEST
   end for;
end DLXTEST;

