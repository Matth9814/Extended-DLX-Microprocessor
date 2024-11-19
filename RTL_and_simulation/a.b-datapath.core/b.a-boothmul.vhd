library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;
use work.constants.all;
use IEEE.math_real.all;

-- GENERAL DESCRIPTION: the booth multiplier implemented here is a pipelined version of the classic
-- boothmul, where the total number of stages is 16. The instructions proceed through the pipeline
-- in a way such that if there are voids (stages occupied by invalid instructions, thing that happens
-- when in a certain clock cycle there is no new multiplication entering the pipeline), the void are
-- filled when the last stage of the pipeline is stalled. In order to make this mechanism clear, let's
-- show the following example: let us suppose that at a certain point the pipeline looks like this
-- 1(entering) | 1 | 1 | 1 | 1 | 0 | 1 | 1 | 0 | 1 | 0 | 1 | 1 | 1 | 1 | 1 | 1 , where 0/1 is the valid bit for each stage
-- and the last stage is stalling (maybe because there is another instruction leaving the execution which
-- is prioritized). At the next cycle the pipeline will be like this:
-- 0(entering) | 1 | 1 | 1 | 1 | 1 | 0 | 1 | 1 | 0 | 1 | 1 | 1 | 1 | 1 | 1 | 1 , because some of the free 
-- spaces have been occupied by instructions which went on in the pipeline (this is very efficient for performances,
-- because if we don't recognize that some stages are void we have to stall the whole pipeline every time there
-- is a stall in the last stage). The remaining voids have been left by instructions which moved from one stage
-- to the next. In order to ensure this behavior, the enable signals for the stages have to be driven in the correct
-- way, in particular a certain pipeline register will be enabled when either it contains an invalid instruction or
-- it contains a valid instruction but this one is moving to the following stage.
-- The mul busy signal is more difficult to drive than the other signals, because it has to be set in situations
-- that are not trivial, for example when there are only 15 stages busy but there is anew instruction coming while the
-- last one is stalling: in this case the last void will be filled, and since the last instruction doesn't leave
-- in the next cc the whole pipeline will be full.

entity BOOTHMUL is
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
end BOOTHMUL;
  
-- mixed structural and behavioral architecture based on Booth’s algorithm
architecture MIXED of BOOTHMUL is

    component MUX51_GENERIC is
        Generic (NBIT: natural:= numBitMultiplier);  
        Port (	X0:	In	std_logic_vector(NBIT-1 downto 0);
                X1:	In	std_logic_vector(NBIT-1 downto 0);
                X2:	In	std_logic_vector(NBIT-1 downto 0);
                X3:	In	std_logic_vector(NBIT-1 downto 0);
                X4:	In	std_logic_vector(NBIT-1 downto 0);
                S:	In	std_logic_vector(2 downto 0);
                Y:	Out	std_logic_vector(NBIT-1 downto 0));
    end component;

    component encoder is    -- the number of decoder is NBITMULTIPLIER/2
      port(B: in std_logic_vector(2 downto 0);
          Sel: out std_logic_vector(2 downto 0));
    end component;

    component P4adder is
      generic(NTOT_P4: natural := numBlocksP4*numBitP4;
          NBLKS_P4: natural := numBlocksP4;
          NBIT_P4: natural := numBitP4);
      port(A,B: in std_logic_vector(NTOT_P4-1 downto 0);
           Cin: in std_logic;
           Cout: out std_logic;
           Sum: out std_logic_vector(NTOT_P4-1 downto 0));
    end component;

    -- Encoder to muxes enable signals
    -- we have a number of them that is equal to the number of encoder stages (NBIT/2)
    type e_to_m is array (0 to NBIT/2-1) of std_logic_vector(2 downto 0);
    -- left muxes to adder signals
    -- one less than the number of stages
    type r_m is array (0 to NBIT/2-2) of std_logic_vector(2*NBIT-1 downto 0);
    -- partial results of an adder which goes to the following adder
    -- the last one will be mapped to the output of the circuit
    type p_r is array (0 to NBIT/2) of std_logic_vector(2*NBIT-1 downto 0);
    -- muxes inputs
    -- since we have NBIT/2 muxes we will create 4 signals of this type, one
    -- for each input to a mux.
    type mux_in_type is array (0 to NBIT/2-1) of std_logic_vector(2*NBIT-1 downto 0);
    signal enc_to_mux: e_to_m;
    signal row_mux: r_m;
    signal partial_res: p_r;
    signal B_row0 : std_logic_vector(2 downto 0);
    -- first input of the first mux
    signal X1_row0: std_logic_vector(2*NBIT-1 downto 0);
    signal X2_row0: std_logic_vector(2*NBIT-1 downto 0);
    signal X3_row0: std_logic_vector(2*NBIT-1 downto 0);
    signal X4_row0: std_logic_vector(2*NBIT-1 downto 0);
    -- array of all inputs 1 to the muxes (the first one is considered explicitly in X1_row0)
    signal X1_rows: mux_in_type;
    -- array of all inputs 2 to the muxes
    signal X2_rows: mux_in_type;
    -- array of all inputs 3 to the muxes
    signal X3_rows: mux_in_type;
    -- array of all inputs 4 to the muxes
    signal X4_rows: mux_in_type;
    signal Cout_dummy: std_logic_vector(15 downto 0);

    -- pipeline registers types
    type Double_Array_Type is array(0 to 17) of std_logic_vector(63 downto 0);
    type Array_Type is array(0 to 17) of std_logic_vector(31 downto 0);
    type ROB_Entry_Type is array(0 to 17) of std_logic_vector(5 downto 0);

    -- carry in signals for the P4adders in the pipeline
    signal Cin_P4_next: std_logic_vector(17 downto 0);
    signal Cin_P4_curr: std_logic_vector(17 downto 0);
    -- carry in signal for the most significant 32 bit adder
    signal Cin_MSP4: std_logic_vector(16 downto 0);
    signal Cin_MSP4_next: std_logic_vector(16 downto 0);

    -- curr values
    signal A_curr: Array_Type;
    signal B_curr: Array_Type;
    signal partial_res_curr: Double_Array_Type;
    signal valid_curr: std_logic_vector(17 downto 0);
    signal ROB_entry_curr: ROB_Entry_Type;

    -- next values
    signal A_next:  Array_Type;
    signal B_next: Array_Type;
    signal partial_res_next: Double_Array_Type;
    signal valid_next: std_logic_vector(17 downto 0);
    signal ROB_entry_next: ROB_Entry_Type;

    -- enables for the pipeline regs
    signal enables: std_logic_vector(18 downto 0);

    -- counter to determine the number of busy stages in the multiplier pipeline
    signal stages_counter: std_logic_vector(4 downto 0);

    signal second_operand_next: Double_Array_Type;
    signal second_operand_curr: Double_Array_Type;

    signal Cin_P4_firstA_next: std_logic_vector(15 downto 0);
    signal Cin_P4_firstA_curr: std_logic_vector(15 downto 0);
    signal Cin_MSP4_15_next: std_logic;
    signal Cin_MSP4_15_curr: std_logic;
    signal B_last: std_logic_vector(31 downto 0);

    begin

      -- counting logic to drive the mul_busy signal, since the busy has to be set in particular conditions depending on the number of busy stages
      process(clk) begin
        if(rising_edge(clk)) then
          if(rst = '1' or h_rst='1') then
            stages_counter <= (others => '0');
          else
            -- up counting
            if(new_mul = '1' and mul_to_mem='0') then
              stages_counter <= std_logic_vector(unsigned(stages_counter)+1);
            end if;
            -- down counting
            if(new_mul = '0' and mul_to_mem='1') then
              stages_counter <= std_logic_vector(unsigned(stages_counter)-1);
            end if;
          end if;
        end if;
      end process;

      -- the mul_busy is set either when the pipeline is full and no instruction is leaving or when there is an empty space but
      -- a new instruction is coming from the dec + no instruction is leaving : in this case we must inform the CU to not send 
      -- another instruction in the next cc, because we don't know if at the end of the next cc there will be space to accomodate
      -- this new instruction.
      mul_busy <= '1' when ((stages_counter="10000" and new_mul='1' and mul_to_mem='0') or (stages_counter="10001" and mul_to_mem='0')) else '0';

      -- pipeline registers
      process(clk, h_rst) begin
        if(h_rst='1') then
          Cin_MSP4_15_curr <= '0';
          Cin_MSP4 <= (others => '0');
          Cin_P4_curr <= (others => '0');
          Cin_P4_firstA_curr <= (others => '0');
          for i in 0 to 17 loop
            A_curr(i) <= (others => '0');
            B_curr(i) <= (others => '0');
            second_operand_curr(i) <= (others => '0');
            partial_res_curr(i) <= (others => '0');
            ROB_entry_curr(i) <= (others => '0');
          end loop;
          valid_curr <= (others => '0');
        elsif(rising_edge(clk)) then
          if(rst='1') then
            Cin_MSP4_15_curr <= '0';
            Cin_MSP4 <= (others => '0');
            Cin_P4_curr <= (others => '0');
            Cin_P4_firstA_curr <= (others => '0');
            for i in 0 to 17 loop
              A_curr(i) <= (others => '0');
              B_curr(i) <= (others => '0');
              second_operand_curr(i) <= (others => '0');
              partial_res_curr(i) <= (others => '0');
              ROB_entry_curr(i) <= (others => '0');
            end loop;
            valid_curr <= (others => '0');
          else
            for i in 0 to 17 loop
              -- enable condition
              if(valid_curr(i)='0' or enables(i)='1') then
                if(i=16) then
                  Cin_MSP4_15_curr <= Cin_MSP4_15_next;
                end if;
                if(i/=0 and i/=16 and i/=17) then
                  Cin_MSP4(i) <= Cin_MSP4_next(i);
                end if;
                if(i/=16 and i/=17) then
                  Cin_P4_firstA_curr(i) <= Cin_P4_firstA_next(i);
                end if;
                valid_curr(i) <= valid_next(i);
                A_curr(i) <= A_next(i);
                B_curr(i) <= B_next(i);
                Cin_P4_curr(i) <= Cin_P4_next(i);
                second_operand_curr(i) <= second_operand_next(i);
                -- pipeline registers with the partial results for operations traversing the pipeline
                partial_res_curr(i) <= partial_res_next(i);
                -- pipeline registers with the ROB entry associated to the instruction currently in each stage
                ROB_entry_curr(i) <= ROB_entry_next(i);
              end if;
            end loop;
          end if;
        end if;
      end process;

      -- mapping last stage to output
      terminal_cnt <= valid_curr(17);
      P <= partial_res_curr(17);
      ROB_entry_out <= ROB_entry_curr(17);

      -- enable generation process and propagation of pipeline signals
      process(A, B, enables, new_mul, mul_to_mem, valid_curr, A_curr, B_curr, ROB_entry_curr) begin
        -- map the last dummy enable to mul_to_mem
        enables(18) <= mul_to_mem;
        for i in 17 downto 0 loop
          if(i=0) then
            valid_next(i) <= new_mul;
            A_next(i) <= A;
            B_next(i) <= B;
            ROB_entry_next(i) <= ROB_entry_in;
            -- enable of the stage i is 1 if either the next stage is enabled (the instruction
            -- currently in stage i will move in i+1 in the next cc, leaving space for the 
            -- one currently in stage i-1) or the stage i contains a void, because this one
            -- can be filled by a valid instruction in the stage i-1.
            enables(i) <= enables(i+1) or (not valid_curr(i));
          else
            -- pipeline signal propagation
            valid_next(i) <= valid_curr(i-1);
            A_next(i) <= A_curr(i-1);
            B_next(i) <= B_curr(i-1);
            ROB_entry_next(i) <= ROB_entry_curr(i-1);
            -- enable generation
            enables(i) <= enables(i+1) or (not valid_curr(i));
          end if;
        end loop;
      end process;

      B_row0 <= B(1 downto 0)&'0';
      -- assignements to the inputs of the first mux
      -- sign extension of A
      X1_row0 <= (2*NBIT-1 downto NBIT => A(NBIT-1)) & A;
      -- -A
      X2_row0 <= std_logic_vector(to_signed(to_integer(signed(not A)),2*NBIT));
      -- 2A
      X3_row0 <= std_logic_vector(shift_left(to_signed(to_integer(signed(A)),2*NBIT),1));
      -- -2A
      X4_row0 <= std_logic_vector(signed(not X3_row0));
      Rows_generation: for i in 0 to (NBIT/2)-1 generate   -- for generate for the encoders
          -- the first row is a particular case because there is no adder
          -- in this case the result of the mux doesn't go into row_mux but it goes into partial_res,
          -- so that the second row can be parameterized together with the following ones.
          first_row: if i=0 generate
            EN0: encoder port map(B=>B_row0,Sel=>enc_to_mux(i));
            MUX0: MUX51_GENERIC generic map(NBIT=>NBIT*2)
                        port map(X0=> (others => '0'),
                                X1=>X1_row0,
                                X2=>X2_row0,
                                X3=>X3_row0,
                                X4=>X4_row0, 
                                S=>enc_to_mux(i),
                                Y => partial_res_next(i));
            X1_rows(i) <= std_logic_vector(shift_left(to_signed(to_integer(signed(A)),2*NBIT),2*(i+1)));
            X2_rows(i) <= std_logic_vector(signed(not X1_rows(i)));
            X3_rows(i) <= std_logic_vector(shift_left(to_signed(to_integer(signed(A)),2*NBIT),2*(i+1)+1));
            X4_rows(i) <= std_logic_vector(signed(not X3_rows(i)));
            EN: encoder port map(B=>B((2*(i+1)+1) downto (2*(i+1)-1)),Sel=>enc_to_mux(i+1));
            MUX: MUX51_GENERIC generic map(NBIT=>NBIT*2)
              port map(X0=> (others => '0'),
                                X1=> X1_rows(i),
                                X2=> X2_rows(i), 
                                X3=> X3_rows(i), 
                                X4=> X4_rows(i), 
                                S=>enc_to_mux(i+1),
                                Y => second_operand_next(i));
            Cin_P4_firstA_next(i) <= '1' when enc_to_mux(i)="010" or enc_to_mux(i)="100" else '0';
            Cin_P4_next(i) <= '1' when enc_to_mux(i+1)="010" or enc_to_mux(i+1)="100" else '0'; 
          end generate;
          other_rows: if i>0 generate
            Cin_P4_firstA_next(i) <= Cin_P4_firstA_curr(i-1);
            SUM_LS: P4adder port map (A=> second_operand_curr(i-1)(31 downto 0),B=>partial_res_curr(i-1)(31 downto 0),
                                  Cin=>Cin_P4_curr(i-1),Cout=>Cin_MSP4_next(i),Sum=>partial_res_next(i)(31 downto 0));
            SUM_MS: P4adder port map (A=> second_operand_curr(i-1)(63 downto 32),B=>partial_res_curr(i-1)(63 downto 32),
                                  Cin=>Cin_MSP4(i-1),Cout=>Cout_dummy(i-1),Sum=>partial_res_next(i)(63 downto 32));
          end generate;
          -- for every row except for the 15th: compute the second input to the adder of the following stage
          every_row_except_15: if i/=15 and i/=0 generate
            X1_rows(i) <= std_logic_vector(shift_left(to_signed(to_integer(signed(A_curr(i-1))),2*NBIT),2*(i+1)));
            X2_rows(i) <= std_logic_vector(signed(not X1_rows(i)));
            X3_rows(i) <= std_logic_vector(shift_left(to_signed(to_integer(signed(A_curr(i-1))),2*NBIT),2*(i+1)+1));
            X4_rows(i) <= std_logic_vector(signed(not X3_rows(i)));
            EN: encoder port map(B=>B_curr(i-1)((2*(i+1)+1) downto (2*(i+1)-1)),Sel=>enc_to_mux(i+1));
            MUX: MUX51_GENERIC generic map(NBIT=>NBIT*2)
              port map(X0=> (others => '0'),
                                X1=> X1_rows(i),
                                X2=> X2_rows(i), 
                                X3=> X3_rows(i), 
                                X4=> X4_rows(i), 
                                S=>enc_to_mux(i+1),
                                Y => second_operand_next(i));
            Cin_P4_next(i) <= '1' when enc_to_mux(i+1)="010" or enc_to_mux(i+1)="100" else '0'; 
          end generate;
      end generate;
    -- stage 16: computation of the LSB part of the result based on the sum between the previous result and the carry corresponding to the C2 due to the first B tuple
    SUM_LS_FINAL: P4adder port map(A => (others => '0'),B => partial_res_curr(15)(31 downto 0),
                                  Cin=>Cin_P4_firstA_curr(15),Cout=>Cin_MSP4_next(16),Sum=>partial_res_next(16)(31 downto 0));
    partial_res_next(16)(63 downto 32) <= partial_res_curr(15)(63 downto 32);
    Cin_MSP4_15_next <= Cin_MSP4(15);
    -- stage 17: computation of the MSB of the result, based on the Cin from the LSB computed in stage 16 and the one from the LSB in stage 15
    B_last <= (31 downto 1 => '0') & Cin_MSP4(16);
    partial_res_next(17)(31 downto 0) <= partial_res_curr(16)(31 downto 0);
    SUM_MS_FINAL: P4adder port map(A => partial_res_curr(16)(63 downto 32),B => B_last,
                                  Cin=>Cin_MSP4_15_curr,Cout=>Cout_dummy(15),Sum=>partial_res_next(17)(63 downto 32));
    end MIXED;

configuration CFG_BOOTHMUL of BOOTHMUL is
  for MIXED
  end for;
end CFG_BOOTHMUL;
