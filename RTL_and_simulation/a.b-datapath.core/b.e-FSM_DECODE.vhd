library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;

entity FSM_DECODE is
    port(
        -- ready signals 
        add_rd: in std_logic;
        log_rd: in std_logic;
        shifter_rd: in std_logic;
        mul_rd: in std_logic;
        div_rd: in std_logic;

        clk: in std_logic;
        rst: in std_logic;
        h_rst: in std_logic;

        -- reset signals
        ALU_out_dec: out std_logic_vector(2 downto 0);
        add_rst: out std_logic;
        log_rst: out std_logic;
        shifter_rst: out std_logic;
        mul_rst: out std_logic;
        div_rst: out std_logic;

        terminal_cnt: out std_logic
    );
end entity;

architecture FSM_ARCH of FSM_DECODE is
    signal stateCurr: std_logic_vector(2 downto 0);
    signal stateNext: std_logic_vector(2 downto 0);
begin
    process(stateCurr, add_rd, log_rd, shifter_rd, mul_rd, div_rd) begin
        -- initial reset for all the signals: only the one that has to be activated will be set in the following case statement
        add_rst <= '0';
        log_rst <= '0';
        shifter_rst <= '0';
        mul_rst <= '0';
        div_rst <= '0';
        case stateCurr is
            when "000" =>
                stateNext <= "001";
                if(add_rd='1') then
                    ALU_out_dec <= "000";
                    add_rst <= '1';
                elsif(log_rd='1') then
                    ALU_out_dec <= "001";
                    log_rst <= '1';
                elsif(shifter_rd='1') then
                    ALU_out_dec <= "010";
                    shifter_rst <= '1';
                elsif(mul_rd='1') then
                    ALU_out_dec <= "011";
                    mul_rst <= '1';
                elsif(div_rd='1') then
                    ALU_out_dec <= "100";
                    div_rst <= '1';
                end if;
            when "001" =>
                stateNext <= "010";
                if(add_rd='1') then
                    ALU_out_dec <= "000";
                    add_rst <= '1';
                elsif(log_rd='1') then
                    ALU_out_dec <= "001";
                    log_rst <= '1';
                elsif(shifter_rd='1') then
                    ALU_out_dec <= "010";
                    shifter_rst <= '1';
                elsif(mul_rd='1') then
                    ALU_out_dec <= "011";
                    mul_rst <= '1';
                elsif(div_rd='1') then
                    ALU_out_dec <= "100";
                    div_rst <= '1';
                end if;
            when "010" =>
                stateNext <= "011";
                if(add_rd='1') then
                    ALU_out_dec <= "000";
                    add_rst <= '1';
                elsif(shifter_rd='1') then
                    ALU_out_dec <= "010";
                    shifter_rst <= '1';
                elsif(mul_rd='1') then
                    ALU_out_dec <= "011";
                    mul_rst <= '1';
                elsif(div_rd='1') then
                    ALU_out_dec <= "100";
                    div_rst <= '1';
                elsif(log_rd='1') then
                    ALU_out_dec <= "001";
                    log_rst <= '1';
                end if;
            when "011" =>
                stateNext <= "100";
                if(add_rd='1') then
                    ALU_out_dec <= "000";
                    add_rst <= '1';
                elsif(mul_rd='1') then
                    ALU_out_dec <= "011";
                    mul_rst <= '1';
                elsif(div_rd='1') then
                    ALU_out_dec <= "100";
                    div_rst <= '1';
                elsif(shifter_rd='1') then
                    ALU_out_dec <= "010";
                    shifter_rst <= '1';
                elsif(log_rd='1') then
                    ALU_out_dec <= "001";
                    log_rst <= '1';
                end if;
            when "100" =>
                stateNext <= "000";
                if(add_rd='1') then
                    ALU_out_dec <= "000";
                    add_rst <= '1';
                elsif(div_rd='1') then
                    ALU_out_dec <= "100";
                    div_rst <= '1';
                elsif(mul_rd='1') then
                    ALU_out_dec <= "011";
                    mul_rst <= '1';
                elsif(log_rd='1') then
                    ALU_out_dec <= "001";
                    log_rst <= '1';
                elsif(shifter_rd='1') then
                    ALU_out_dec <= "010";
                    shifter_rst <= '1';
                end if;
            when others =>
                stateNext <= "000";
        end case;
    end process;

    terminal_cnt <= '1' when add_rd='1' or log_rd='1' or shifter_rd='1' or mul_rd='1' or div_rd='1' else '0';

    process (clk,rst,h_rst) begin
        if(rst='1' or h_rst='1') then
            stateCurr <= "000";
        elsif(rising_edge(clk)) then
            if(add_rd='1' or log_rd='1' or shifter_rd='1' or mul_rd='1' or div_rd='1') then
                stateCurr <= stateNext;
            end if;
        end if;
    end process;

end FSM_ARCH;