library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;
use WORK.constants.all;
use IEEE.math_real.all;

entity RAT is
    port(
        RD1: in std_logic_vector(4 downto 0); -- first operand
        RD2: in std_logic_vector(4 downto 0); -- second operand
        WR2: in std_logic_vector(4 downto 0); -- register where the result has to be written, updated in decode
        WR1: in std_logic_vector(4 downto 0); -- register where the result of the istruction in commit has to be written, modified during commit
        inp: in std_logic_vector(5 downto 0); -- ROB entry associated to WR2 register
        inv: in std_logic; -- 1 if the entry corresponding to WR1 must be invalidated (during the commit phase)
        WR2_en: in std_logic; -- 1 if the entry corresponding to WR2 must be overwritten with inp (during decode and ROB allocation)
        clk: in std_logic;
        rst: in std_logic; -- raised when there is the commit of a mispredicted branch
        h_rst: in std_logic; -- reset of the whole core
        rob_entry_to_be_deleted: in std_logic_vector(5 downto 0); -- WR1 entry is invalidated only if its content is equal to this input

        out1: out std_logic_vector(5 downto 0); -- rob entry associated to the first operand
        out2: out std_logic_vector(5 downto 0); -- rob entry associated to the second operand
        out1_valid: out std_logic; -- 1 if the RD1 entry is valid in the RAT
        out2_valid: out std_logic -- 1 if the RD2 entry is valid in the RAT

    );
end RAT;

architecture RAT_behavioral of RAT is

type StorageT is array(0 to 31) of std_logic_vector(5 downto 0);
signal RAT_mem: StorageT;
signal valid_array: std_logic_vector(0 to 31);
signal inv_int: std_logic;

begin
    -- write and reset
    process(clk,h_rst) begin
        if(h_rst='1') then
            for i in 0 to 31 loop
                valid_array(i) <= '0';
            end loop;
        elsif(rising_edge(clk)) then
            if(rst='1') then
                for i in 0 to 31 loop
                    valid_array(i) <= '0';
                end loop;
            else
                if(inv_int='1') then
                    valid_array(to_integer(unsigned(WR1))) <= '0';
                end if;
                if(WR2_en='1') then
                    valid_array(to_integer(unsigned(WR2))) <= '1';
                    RAT_mem(to_integer(unsigned(WR2))) <= inp;
                end if;
            end if;
        end if;
    end process;

    -- we invalidate the entry WR1 if the value written there is equal to the ROB entry we are planning on deleting
    inv_int <= '1' when inv='1' and RAT_mem(to_integer(unsigned(WR1)))=rob_entry_to_be_deleted else '0';

    out1 <= RAT_mem(to_integer(unsigned(RD1)));
    out2 <= RAT_mem(to_integer(unsigned(RD2)));
    out1_valid <= valid_array(to_integer(unsigned(RD1)));
    out2_valid <= valid_array(to_integer(unsigned(RD2)));

end RAT_behavioral;