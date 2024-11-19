library ieee;
use ieee.std_logic_1164.all;

package CONSTANTS is
        -- operations which use the adder (0)
        constant ADD_OP : std_logic_vector(4 downto 0) := "00001";
        constant SGE_OP : std_logic_vector(4 downto 0) := "00010"; 
        constant SNE_OP : std_logic_vector(4 downto 0) := "00011";
        constant SLE_OP : std_logic_vector(4 downto 0) := "00100"; 
        constant SUB_OP : std_logic_vector(4 downto 0) := "00101"; 
        -- operations which use the shifter (10)
        constant SLL_OP : std_logic_vector(4 downto 0) := "10000";
        constant SRL_OP : std_logic_vector(4 downto 0) := "10001";
        -- operations which use the mul (11110)
        constant MUL_OP : std_logic_vector(4 downto 0) := "11110";
        -- operations which use the div (11111)
        constant DIV_OP : std_logic_vector(4 downto 0) := "11111";
        -- operations which use the logicals (110)
        constant AND_OP : std_logic_vector(4 downto 0) := "11000"; 
        constant OR_OP  : std_logic_vector(4 downto 0) := "11001"; 
        constant XOR_OP : std_logic_vector(4 downto 0) := "11010";
        -- nop, it shouldn't arrive in execute (because it is recognized as a nop in decode and the allocation in the ROB is not performed)
        constant NOP_OP : std_logic_vector(4 downto 0) := "00000";
        constant PAR : natural := 32; -- default parallelism for DLX architecture
        constant numBit : natural := 32; -- Normal Registers/Operands dimension 
        constant numBitMultiplier: natural := 32;
        constant ivdelay: time := 0 ns;
        constant nddelay: time := 0 ns;
        constant numBitP4: natural := 4;
        constant numBlocksP4: natural := 8; 
        constant numReg: natural := 32;
        constant numBitReg: natural := 32;
end CONSTANTS;
