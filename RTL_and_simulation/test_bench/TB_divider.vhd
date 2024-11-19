library IEEE;
use IEEE.std_logic_1164.all;
use ieee.numeric_std.all;
use work.constants.all;
use IEEE.math_real.all;

entity TB_DIVIDER is
end TB_DIVIDER;

architecture TEST of TB_DIVIDER is
	
	component divider is
        generic(NBIT: natural := numBit;
                STEPBIT: natural := natural(log2(real(numBit)))+1);
                -- The algorithm needs 32 step to iterate over each bit of the reminder +
                -- one additional clock cycle to restore the last reminder and change the last bit of the
                -- quotient if Rn<0
                -- The counter has to go from 0 to 32 so it is on 6 bits
        port(
            Z: in std_logic_vector(NBIT-1 downto 0); -- dividend
            D: in std_logic_vector(NBIT-1 downto 0); -- divisor
            Q: out std_logic_vector(NBIT-1 downto 0); -- quotient
            R: out std_logic_vector(NBIT-1 downto 0); -- reminder
            opType: in std_logic; -- Operation type
            clk: in std_logic;
            enable: in std_logic; -- Asynch reset
            OpEnd: out std_logic -- Operation finished
        );
    end component;
    
    constant NBIT : natural := numBit;
    constant STEPBIT: natural := natural(log2(real(numBit)))+1;
    constant HCLKP: time := 5 ns;
	signal Z_s,D_s,Q_s,R_s: std_logic_vector(NBIT-1 downto 0);
    signal clk_s, enable_s, opEnd_s, opType_s: std_logic;

begin
	DUT: DIVIDER port map(Z=>Z_s,D=>D_s,Q=>Q_s,R=>R_s,opType=>opType_s,clk=>clk_s,enable=>enable_s,opEnd=>opEnd_s);
	
    process
    begin
        clk_s <= '0';
        wait for HCLKP;
        clk_s <= '1';
        wait for HCLKP;
    end process;

    process
    begin
        enable_s <= '0'; -- Reset   
        wait until rising_edge(clk_s);
        wait for 2 ns;

        -- 0 Division
        enable_s<='1';
        opType_s <= '0';
        Z_s <= x"0000_0006";
        D_s <= x"0000_0000";

        wait for 2*HCLKP;
        enable_s <= '0';
        wait for 2*HCLKP;
        
        -- UNSIGNED values -- NO RESTORE of the REMINDER
        enable_s <= '1';
        -- The divider works only with unsigned numbers and the highest unsigned on 32 bits
        -- using a 2's complement representation is 7FFF_FFFF
        opType_s <= '0';
        Z_s <= x"0000_0006";
        D_s <= x"0000_0002";
        --D_s <= x"FFFF_FFFF";
        --wait for HCLKP;

        -- #actual division steps = #bits
        -- Division cycles (Setup + 32 + Restore check) -- No conversion Z,D > 0
        for i in 0 to NBIT loop 
            wait for 2*HCLKP; 
        end loop;

        wait for 2*HCLKP;
        enable_s <= '0';
        wait for 2*HCLKP;
        
        -- TEST: 2 Division IN A ROW

        -- UNSIGNED values -- RESTORE of the REMINDER
        -- The quotient has to have LSB=0 and LSB+1=1
        opType_s <= '0';
        enable_s <= '1';
        Z_s <= x"0000_000A"; -- Z=10
        D_s <= x"0000_0004";
        -- R=0000_0002
        for i in 0 to NBIT loop
            wait for 2*HCLKP;
        end loop;

        wait for 2*HCLKP;
        enable_s <= '0';
        wait for 2*HCLKP;

        -- SIGNED values -- Z < 0 and D > 0
        opType_s <= '1';
        enable_s <= '1';
        Z_s <= x"FFFF_FFF0"; -- Z=-16
        D_s <= x"0000_0003";
        -- R=FFFF_FFFF < 0
        -- Q=FFFF_FFFB < 0

        -- Division cycles (Setup + 32 + Restore check + 2 Conversion cycles) -- No conversion Z,D > 0
        for i in 0 to NBIT+2 loop
            wait for 2*HCLKP;
        end loop;

        wait for 2*HCLKP;
        enable_s <= '0';
        wait for 2*HCLKP;

        -- SIGNED values -- Z > 0 and D < 0
        opType_s <= '1';
        enable_s <= '1';
        Z_s <= x"0000_000A"; -- Z=10
        D_s <= x"FFFF_FFFC"; -- D=-4
        -- R=0000_0002 > 0
        -- Q=FFFF_FFFE < 0

        -- Division cycles (Setup + 32 + Restore check + 1 Conversion cycle) -- No conversion Z,D > 0
        for i in 0 to NBIT+1 loop
            wait for 2*HCLKP;
        end loop;

        wait for 2*HCLKP;
        enable_s <= '0';
        wait for 2*HCLKP;

        -- SIGNED values -- Z < 0 and D < 0
        opType_s <= '1';
        enable_s <= '1';
        Z_s <= x"FFFF_FFF0"; -- Z=-16
        D_s <= x"FFFF_FFFB"; -- D=-5
        -- R=FFFF_FFFF > 0
        -- Q=0000_0003 < 0

        -- Division cycles (2 Setup cycles + 32 + Restore check + 1 Conversion cycles) -- No conversion Z,D > 0
        for i in 0 to NBIT+2 loop
            wait for 2*HCLKP;
        end loop;

        wait for 2*HCLKP;
        enable_s <='0';
        wait for 2*HCLKP;

        wait;
    end process;
end TEST;

configuration TEST_DIVIDER of TB_DIVIDER is
	for TEST
    end for;
end configuration;

