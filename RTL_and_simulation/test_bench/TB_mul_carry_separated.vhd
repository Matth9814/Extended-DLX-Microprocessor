library IEEE;
use IEEE.std_logic_1164.all;
use WORK.constants.all;
use IEEE.math_real.all;

entity TB_BOOTHMUL_CARRY_SEPARATED is
end TB_BOOTHMUL_CARRY_SEPARATED;

architecture TEST of TB_BOOTHMUL_CARRY_SEPARATED is

    component BOOTHMUL is
        generic (NBIT: natural := 32);
        port(
             A: in std_logic_vector(NBIT-1 downto 0);
             B: in std_logic_vector(NBIT-1 downto 0);
             P: out std_logic_vector(2*NBIT-1 downto 0);
             clk: in std_logic;
             terminal_cnt: out std_logic;
             rst: in std_logic; -- to be used in case of mispredictions, when there is the need to flush the entire pipeline after the decode
             h_rst: in std_logic;
             new_mul: in std_logic; -- a new mul is entering the pipeline (a 0 val means that no new mul is entering)
             mul_to_mem: in std_logic; -- a multiplication is leaving the EXE unit
             mul_busy: out std_logic; -- if 15 or 16 slots of the mul are taken
    
             -- input information related to the instructions passing through the pipeline
             ROB_entry_in: in std_logic_vector(5 downto 0);
    
             -- output information
             ROB_entry_out: out std_logic_vector(5 downto 0)
            );
    end component;

    signal A: std_logic_vector(31 downto 0);
    signal B: std_logic_vector(31 downto 0);
    signal P: std_logic_vector(63 downto 0);
    signal clk: std_logic;
    signal terminal_cnt: std_logic;
    signal rst: std_logic;
    signal h_rst: std_logic;
    signal new_mul: std_logic;
    signal mul_to_mem: std_logic;
    signal mul_busy: std_logic;
    signal ROB_entry_in: std_logic_vector(5 downto 0);
    signal ROB_entry_out: std_logic_vector(5 downto 0);

begin

    process begin
        clk <= '0';
        wait for 5 ns;
        clk <= '1';
        wait for 5 ns;
    end process;

    boothmul_P4: boothmul port map (A=>A,B=>B,P=>P,clk=>clk,terminal_cnt=>terminal_cnt, rst=>rst,
                                h_rst=>h_rst,new_mul=>new_mul,mul_to_mem=>mul_to_mem,mul_busy=>mul_busy,
                                ROB_entry_in=>ROB_entry_in,ROB_entry_out=>ROB_entry_out);
    
    process begin
        -- initial reset
        h_rst <= '1';
        mul_to_mem <= '0';
        wait for 1 ns;
        h_rst <= '0';
        new_mul <= '1';
        -- the timing is handled inside the unit
        A <= "00000000000000000000000000000110";
        B <= "00000000000000000000000000000100";
        wait for 10 ns;
        new_mul <= '1';
        A <= "01000000000000000000000000001000";
        B <= "00000000000000000000000100000010";
        wait for 10 ns;
        new_mul <= '0';
        wait until terminal_cnt='1';
        wait for 0.1 ns;
        mul_to_mem <= '1';
        assert P="0000000000000000000000000000000000000000000000000000000000011000" report "wrong res 1";
        wait until rising_edge(clk);
        wait for 0.1 ns;
        mul_to_mem <= '1';
        -- second test with MSBs
        A <= "11000000000000000000000000100110";
        B <= "00000000000000000000000100000100";
        new_mul <= '1';
        assert P="0000000000000000000000000100000010000000000000000000100000010000" report "wrong res 1.1";
        wait for 10 ns;
        new_mul <= '0';
        wait until terminal_cnt='1';
        wait for 0.1 ns;
        mul_to_mem <= '1';
        assert P="1111111111111111111111111011111100000000000000000010011010011000" report "wrong res 2";
        wait;
    end process;
end TEST;

configuration BOOTHTEST of TB_BOOTHMUL_CARRY_SEPARATED is
    for TEST
    end for;
 end BOOTHTEST;