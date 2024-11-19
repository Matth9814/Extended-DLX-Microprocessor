library IEEE;
use IEEE.std_logic_1164.all;
use work.constants.all;

entity LOGICALS is
    generic (NBIT: natural := numBit);
    port(R1: in std_logic_vector(NBIT-1 downto 0);
         R2: in std_logic_vector(NBIT-1 downto 0);
         S0: in std_logic;
         S1: in std_logic;
         S2: in std_logic;
         S3: in std_logic;
         Res: out std_logic_vector(NBIT-1 downto 0)
        );
  end LOGICALS;
  
architecture BEHAVIORAL of LOGICALS is

    signal L0: std_logic_vector(NBIT-1 downto 0);   -- intermediate output
    signal L1: std_logic_vector(NBIT-1 downto 0);   -- intermediate output
    signal L2: std_logic_vector(NBIT-1 downto 0);   -- intermediate output
    signal L3: std_logic_vector(NBIT-1 downto 0);   -- intermediate output

begin
    sign_extension: for i in 0 to NBIT-1 generate  
    -- Figure 4.8 Logicals T2
        L0(i) <= not(S0 and not(R1(i)) and not(R2(i)));
        L1(i) <= not(S1 and not(R1(i)) and R2(i));
        L2(i) <= not(S2 and R1(i) and not(R2(i)));
        L3(i) <= not(S3 and R1(i) and R2(i));
        Res(i) <= not(L0(i) and L1(i) and L2(i) and L3(i)); -- Output
    end generate;
end BEHAVIORAL;

architecture BEHAVIORAL2 of LOGICALS is
    -- The mapped post-synthesis design is the same as BEHAVIORAL (both implemented with muxes)
    -- both in terms of time and area (check the reports)
    signal L0,L1,L2,L3: std_logic_vector(NBIT-1 downto 0);
begin
    structure: for i in 0 to NBIT-1 generate
        L0(i) <= not(S0 nand not(R1(i))) nand not(R2(i));
        L1(i) <= not(S1 nand not(R1(i))) nand R2(i);
        L2(i) <= not(S2 nand R1(i)) nand not(R2(i));
        L3(i) <= not(S3 nand R1(i)) nand R2(i);
        Res(i) <= not(L0(i) nand L1(i)) nand not(L2(i) nand L3(i)); -- Output
    end generate;
end BEHAVIORAL2;

-- The structural implementations with NAND3 and NAND4 is more area consuming than BEHAV (178 vs 212)
-- but it's slightly faster (0.04 lass than BEHAV)
architecture STRUCTURAL of LOGICALS is
    component ND3 is
        Port (A: in	std_logic;
            B: in std_logic;
            C: in std_logic;
            Y: out std_logic);
    end component;
    
    component ND4 is
        Port (A: in	std_logic;
            B: in std_logic;
            C: in std_logic;
            D: in std_logic;
            Y: out std_logic);
    end component;    

    signal L0,L1,L2,L3: std_logic_vector(NBIT-1 downto 0);
    signal R1_inv, R2_inv: std_logic_vector(NBIT-1 downto 0);
begin
    -- Signals in port maps need to be statically defined
    R1_inv <= not(R1);
    R2_inv <= not(R2);
    struct: for i in 0 to NBIT-1 generate
        NAND3_0: nd3 port map (A=>S0,B=>R1_inv(i),C=>R2_inv(i),Y=>L0(i));
        NAND3_1: nd3 port map (A=>S1,B=>R1_inv(i),C=>R2(i),Y=>L1(i));
        NAND3_2: nd3 port map (A=>S2,B=>R1(i),C=>R2_inv(i),Y=>L2(i));
        NAND3_3: nd3 port map (A=>S3,B=>R1(i),C=>R2(i),Y=>L3(i));
        NAND4_0: nd4 port map (A=>L0(i),B=>L1(i),C=>L2(i),D=>L3(i),Y=>Res(i));
    end generate;
end STRUCTURAL;

configuration CFG_LOGICALS_BEHAV of LOGICALS is
  for BEHAVIORAL
  end for;
end CFG_LOGICALS_BEHAV;

configuration CFG_LOGICALS_BEHAV2 of LOGICALS is
    for BEHAVIORAL2
    end for;
  end CFG_LOGICALS_BEHAV2;  

configuration CFG_LOGICALS_STRUCT of LOGICALS is
    for STRUCTURAL
        for struct
            for NAND3_0: nd3
                use configuration work.CFG_ND3_BEHAV;
            end for;
            for NAND3_1: nd3
                use configuration work.CFG_ND3_BEHAV;
            end for;
            for NAND3_2: nd3
                use configuration work.CFG_ND3_BEHAV;
            end for;
            for NAND3_3: nd3
                use configuration work.CFG_ND3_BEHAV;
            end for;
            for NAND4_0: nd4
                use configuration work.CFG_ND4_BEHAV;
            end for;
        end for;
    end for;
  end CFG_LOGICALS_STRUCT;