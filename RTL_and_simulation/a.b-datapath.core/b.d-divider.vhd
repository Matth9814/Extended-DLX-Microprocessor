library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;
use IEEE.math_real.all;
use work.constants.all;

-- NON-RESTORING algorithm DIVIDER for UNSIGNED numbers
-- 0. Load Q=Z (dividend), A=0 (remainder) and D=divisor
-- 1. Check sign of A
--      if 1 (negative): left shift AQ and then A=A+D
--      if 0 (positive): left shift AQ and then A=A-D
-- 2. Check sign of A
--      if 1 (negative): Q[0]=0
--      if 0 (positive): Q[0]=1
-- 3. Check N (step) (countdown from 31)
--      if 0: A=A+M (restore the remainder)
--      else: go to step 1 
-- END: the quotient is in Q and the remainder is in A

-- NOTE:
-- The algorithm on the notes draft is similar but still different than the one described above
-- and, due to the assumptions on the operand, is poorly directly implementable in hardware. 

-- DISCARDED IMPROVEMENTS:
-- + STEP 1 is necessary also if the operation is on signed only because 1000_0000 (-2^32)
--   is on 32 bit when turned in unsigned (all other values in c2 on 32 bits are on 31 effective bits
--   when turned into unsigned) 
-- + Converting Q/R when necessary on LASTSTEP if a restore was not needed would have saved 1 cycle in some occasions
--   but it had too many cases (8) to code

entity divider is
    generic(NBIT: natural := numBit;
            STEPBIT: natural := natural(log2(real(numBit)))+1);
            -- The algorithm needs 32 step to iterate over each bit of the remainder +
            -- one additional clock cycle to restore the last remainder and change the last bit of the
            -- quotient if Rn<0
            -- The counter has to go from 0 to 32 so it is on 6 bits
    port(
        Z: in std_logic_vector(NBIT-1 downto 0); -- dividend
        D: in std_logic_vector(NBIT-1 downto 0); -- divisor
        Q: out std_logic_vector(NBIT-1 downto 0); -- quotient
        R: out std_logic_vector(NBIT-1 downto 0); -- remainder
        opType: in std_logic; -- 1/0 Signed/Unsigned
        clk: in std_logic;
        enable: in std_logic; -- Enable ACTIVE HIGH -- also used for registers reset
        OpEnd: out std_logic -- Operation finished
    );
end divider;

architecture MIXED of divider is
    
    component P4adder is
        generic(NTOT_P4: natural := numBlocksP4*numBitP4;
                NBLKS_P4: natural := numBlocksP4;
                NBIT_P4: natural := numBitP4);
        port(A,B: in std_logic_vector(NTOT_P4-1 downto 0);
             Cin: in std_logic;
             Cout: out std_logic;
             Sum: out std_logic_vector(NTOT_P4-1 downto 0));
    end component;
    
    component PIPO is -- Parallel In/Out register
    generic (NBIT: integer := numBit);
        Port(D:	In std_logic_vector(NBIT-1 downto 0);
            CLK:	In std_logic;
            RST: In	std_logic; -- Asynch
            LOAD: In std_logic; -- 1/0 Load/Memory
            Q: Out std_logic_vector(NBIT-1 downto 0));
    end component;

    component LEFT_SHIFTER is
        generic (NBIT: natural := numBit);
        port(
            I: in std_logic_vector(NBIT-1 downto 0);
            Q: out std_logic_vector(NBIT-1 downto 0);
            load: in std_logic_vector(1 downto 0);
            -- 00 SERIAL LOAD
            -- 01 PARALLEL LOAD
            -- 10 MEMORY
            rst: in std_logic; -- Asynch
            clk: in std_logic
        );
    end component;

    component SYNCH_UPCOUNTER is -- Synchronous Up Counter
        generic (NBIT: integer := natural(log2(real(numBit)))+1);
	Port(
		COUNT: In std_logic; -- 1/0 Count/Not count
		Q: Out std_logic_vector(NBIT-1 downto 0);
        CLK: In	std_logic;
		RST: In	std_logic -- Asynch
		);
    end component;

    -- Adder signals
    signal opB: std_logic_vector(NBIT-1 downto 0); -- Divider
    signal opA: std_logic_vector(NBIT-1 downto 0); -- remainder
    signal Cin, Cout: std_logic;
    signal Sum: std_logic_vector(NBIT-1 downto 0); 
    -- A=A +/- D and operands conversion signed->unsigned->signed

    -- remainder (A) signals
    signal currA,nextA: std_logic_vector(NBIT-1 downto 0);
    signal loadA: std_logic;
    -- std_logic and 1 bit std_logic_vector are not compatible
    signal currSignR,nextSignR: std_logic_vector(0 downto 0);
    signal loadSignQR: std_logic;
    
    -- Divider (D) signals
    signal currD,nextD: std_logic_vector(NBIT-1 downto 0);
    signal loadD: std_logic;

    -- Quotient (Q) signals
    signal currQ,nextQ: std_logic_vector(NBIT-1 downto 0);
    signal loadQ: std_logic_vector(1 downto 0);
    signal currSignQ,nextSignQ: std_logic_vector(0 downto 0);
    
    -- Step Counter signals
    signal count: std_logic;
    signal step: std_logic_vector(STEPBIT-1 downto 0);
    constant LastStep: std_logic_vector(STEPBIT-1 downto 0) := "100001";
    
    -- Conversion state signals
    signal cntConv: std_logic;
    signal stateConv: std_logic_vector(0 downto 0);

    -- Registers reset
    signal rstRegs: std_logic;

    -- Operation end signals
    signal currOpEnd, nextOpEnd: std_logic;

begin
    -- Divider logic
    DIV_LOGIC: process (step, currA, currQ, currD, D, Z, Sum, opType, stateConv, currSignQ, currSignR, currOpEnd)
        variable longsetup: std_logic;
    begin
        if(currOpEnd = '0') then
            loadD <= '0'; -- Memory
            loadA <= '0';
            loadQ <= "10";
            loadSignQR <= '0';
            cntConv <= '0';
            count <= '0';
            nextOpEnd <= currOpEnd;
            if step="000000" then -- Setup
                if D=x"0000_0000" then
                    nextOpEnd <= '1';
                else
                    -- opType   SignD   SignZ                                   
                    -- 0        x       x       --> unsigned operation          
                    -- 1        0       0       --> unsigned operation          
                    -- 1        0       1       --> signed op (1 setup cycle)   
                    -- 1        1       0       --> signed op (1 setup cycle)   
                    -- 1        1       1       --> signed op (2 setup cycle)   
                    
                    loadD <= '1';
                    loadA <= '1';
                    loadQ <= "01";
                    loadSignQR <= '1';
                    cntConv <= '0';
                    count <= '1';
                    nextA <= (others => '0');

                    -- 1 bit signals declared as std_logic_vector for type compatibility with
                    -- the used components
                    nextSignQ(0) <= (D(NBIT-1) xor Z(NBIT-1)) and opType;
                    nextSignR(0) <= Z(NBIT-1) and opType;
                    -- In the Computer Science definition of integer division the formula
                    -- Z=Q*D+R is valid also if Z is negative
                    -- In the mathematic definition it wouldn't as explained here:
                    -- http://utenti.quipo.it/base5/numeri/divquotresto.htm

                    if opType='0' or not(D(NBIT-1) or Z(NBIT-1))='1' then -- UNSIGNED OP

                        nextD <= D;
                        nextQ <= Z;

                    elsif (D(NBIT-1)='1' and Z(NBIT-1)='1') or stateConv(0)='1' then -- SIGNED OP with 2 SETUP cycle
                    -- The condition on stateConv(0) avoids to have to keep Z and D on the input
                    -- for 2 clock cycles
                        cntConv <= '1'; -- stateConv='0' #1 setup cycle
                                        -- stateConv='1' #2 setup cycle
                                        -- stateConv='0' STEP=1

                        -- The algorithm works only with unsigned values so if D/Z < 0 
                        -- a conversion is needed

                        -- Stores D in its register if both Z,D < 0
                        -- Avoid to use an additional register to keep D on the input for
                        -- 2 clock cycles (it would be actually useful only if Z,D < 0 since in
                        -- the first setup cycle we convert Z). 
                        if stateConv(0)='0' then -- #1 Setup cycle
                            count <= '0';
                            nextD <= D;
                            opA <= (others => '0');
                            opB <= not(Z);
                            Cin <= '1';
                            nextQ <= Sum;
                        else -- #2 Setup cycle
                            loadSignQR <= '0';
                            loadQ <= "10"; -- Z has been loaded in the previous cycle
                            opA <= (others => '0');
                            opB <= not(currD);
                            Cin <= '1';
                            nextD <= Sum; 
                        end if;
                    else -- SIGNED OP with 1 SETUP cycle
                        if D(NBIT-1)='1' then
                            opA <= (others => '0');
                            opB <= not(D);
                            Cin <= '1';
                            nextD <= Sum;
                            nextQ <= Z;
                        else
                            opA <= (others => '0');
                            opB <= not(Z);
                            Cin <= '1';
                            nextQ <= Sum;
                            nextD <= D;
                        end if;
                    end if;
                end if;
            elsif step=LASTSTEP then
                loadD <= '0'; -- Memory
                loadA <= '0'; -- Memory
                loadQ <= "00"; -- Serial load
                count <= '1';

                nextQ(0) <= not(currA(NBIT-1)); -- Quotient LSB

                if currA(NBIT-1)='1' then -- RESTORE NEEDED
                    -- A does not need to be left shifted in the "RESTORE" cycle
                    opA <= currA;
                    opB <= currD;
                    Cin <= '0';
                    -- Load the result on the last step if A need to be restored
                    loadA <= '1';
                    nextA <= Sum;
                end if;
                
                if (currSignQ(0) or currSignR(0))='0' then -- Q,R > 0
                    -- If there is no conversion to be done the operation is completed
                    -- so we use the next clock cycle to reset the registers and the counter
                    nextOpEnd <= '1';
                    count <= '0'; -- No additional operation cycle
                end if;
            elsif step=std_logic_vector(unsigned(LASTSTEP)+1) then
                loadD <= '0'; -- Memory
                loadA <= '0'; -- Memory
                loadQ <= "10"; -- Memory
                count <= '0';

                if (currSignQ(0) and currSignR(0))='1' then -- 2 Conversion cycles
                    cntConv <= '1';
                    if stateConv(0)='0' then -- Quotient conversion
                        loadQ <= "01"; -- Parallel load
                        opA <= (others => '0');
                        opB <= not(currQ);
                        Cin <= '1';
                        nextQ <= Sum; -- Store the converted Q since we still need to convert R
                        -- A is in memory
                    else
                        loadA <= '1';
                        opA <= (others => '0');
                        opB <= not(currA);
                        Cin <= '1';
                        nextA <= Sum;
                        nextOpEnd <= '1';
                    end if;
                else -- 1 Conversion cycle
                    if currSignQ(0)='1' then -- Convert Q
                        loadQ <= "01"; -- Parallel load
                        opA <= (others => '0');
                        opB <= not(currQ);
                        Cin <= '1';
                        nextQ <= Sum;
                    else -- Convert R
                        loadA <= '1';
                        opA <= (others => '0');
                        opB <= not(currA);
                        Cin <= '1';
                        nextA <= Sum;
                    end if;
                    nextOpEnd <= '1';
                end if;
            else -- All algorithm steps except the last and the setup/final ones
                loadD <= '0'; -- Memory
                loadA <= '1'; -- Parallel load
                loadQ <= "00"; -- Serial load
                count <= '1';
                
                -- The bit inserted at STEP 1 is not Q[MSB], it is just a dummy bit
                -- The quotient bit evaluated at STEP i is the (34-i)th bit of the final quotient
                -- STEP 1: Dummy bit
                -- STEP 2: MSB and so on
                nextQ(0) <= not(currA(NBIT-1));
                
                -- The A register left shift is not implemented using a shift register since it
                -- would waste a clock cycle. It can be done with proper wiring.
                opA <= currA(NBIT-2 downto 0) & currQ(NBIT-1);
                
                if currA(NBIT-1)='0' then -- A > 0
                    opB <= not(currD);
                else -- A < 0
                    opB <= currD;
                end if;

                Cin <= not(currA(NBIT-1)); -- 1/0 if A[MSB]=0/1

                nextA <= Sum; -- Adder output
            end if;
        end if;
    end process;

    OPEND_LOGIC: process(clk)
    begin
        if rising_edge(clk) then
            if enable='0' then
                currOpEnd <= '0';
            else
                currOpEnd <= nextOpEnd;
            end if;
        end if;
    end process;

    Q <= currQ;
    R <= currA;
    opEnd <= currOpEnd;
    rstRegs <= not(enable);

    -- The DIVIDER register is not necessary if D is kept on the input for the entire duration of the division
    DividerReg: PIPO port map (D=>nextD,clk=>clk,rst=>rstRegs,load=>loadD, Q=>currD);
    AddSub: P4ADDER generic map (NTOT_P4 => 32, NBIT_P4 => 4, NBLKS_P4 => 8) port map(A=>opA, B=>opB, Cin=>Cin, Cout=>Cout, Sum=>Sum);
    RemainderReg: PIPO port map(D=>nextA,clk=>clk,rst=>rstRegs,load=>loadA, Q=>currA);
    QuotientReg: LEFT_SHIFTER port map(I=>nextQ,Q=>currQ,load=>loadQ,rst=>rstRegs,clk=>clk);
    StepCounter: SYNCH_UPCOUNTER port map (count=>count,Q=>step,clk=>clk,rst=>rstRegs);
    Sign_Q: PIPO generic map(NBIT=>1) 
        port map(D=>nextSignQ,clk=>clk,rst=>rstRegs,load=>loadSignQR,Q=>currSignQ);
    Sign_R: PIPO generic map(NBIT=>1) 
        port map(D=>nextSignR,clk=>clk,rst=>rstRegs,load=>loadSignQR,Q=>currSignR);
    ConvState: SYNCH_UPCOUNTER generic map(NBIT=>1)
        port map(count=>cntConv,Q=>stateConv,clk=>clk,rst=>rstRegs);
end MIXED;

configuration CFG_DIV_STRUCTURAL of divider is
    for MIXED
        for DividerReg: PIPO
            use configuration work.CFG_PIPO_BEHAVIORAL;
        end for;
        for AddSub: P4ADDER
            use configuration work.CFG_P4adder_STRUCTURAL;
        end for;
        for RemainderReg: PIPO
            use configuration work.CFG_PIPO_BEHAVIORAL;
        end for;
        for QuotientReg: LEFT_SHIFTER
            use configuration work.CFG_LSHIFTER_BEHAVIORAL;
        end for;
        for StepCounter: SYNCH_UPCOUNTER
            use configuration work.CFG_SYUPCNT_BEHAVIORAL;
        end for;
        for Sign_Q: PIPO
            use configuration work.CFG_PIPO_BEHAVIORAL;
        end for;
        for Sign_R: PIPO
            use configuration work.CFG_PIPO_BEHAVIORAL;
        end for;
        for ConvState: SYNCH_UPCOUNTER
            use configuration work.CFG_SYUPCNT_BEHAVIORAL;
        end for;
    end for;
end CFG_DIV_STRUCTURAL;