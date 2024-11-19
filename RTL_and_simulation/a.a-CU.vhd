library ieee;
use ieee.std_logic_1164.all;
use work.constants.all;
use ieee.numeric_std.all;

-- IMPORTANT: THE MEANING OF RESETS AND ENABLE HAS CHANGED! In particular, whenever an enable is low, the
-- corresponding register is reset too, thanks to some circuitry in the datapath. The reset signals has to be
-- used only to reset the whole stage, included the registers in the middle of stage (for example the 
-- D2E register has to be reset every time there is no instruction ready, but the contents of the inner
-- registers must not be affected by the reset! The true reset of the stage happens only when a misprediction
-- is performed.)
-- BUT PAY ATTENTION TO THE F2D REGISTER, BECAUSE IT CAN'T BE RESET! If we reset it we lose information
-- about the current instruction that should be sent to the exe stage at the next clock cycle. Devise a circuit
-- able to stop the allocation of new entries in the ROB when the decode stage has stalled for at least one cc,
-- otherwise we risk filling the ROB with garbage.
-- WHILE INSTEAD THE M2WB SHOULD BE ALWAYS RESET IF IT IS STALLING (otherwise in all the following clock cycles
-- a terminated instruction is recognized, thus invalidating the conditions to determine if there is an hazard undergoing)

-- in order to determine if an instruction in a stage is valid you can pass to the register before the stage a
-- valid bit, which is used to reset the register before the stage that the instruction is leaving (for example
-- the value of the valid bit in memory is used to reset the E2M register. In order for this to work, this value
-- must be used in AND with the enable of the stage before negated). In the EXE stage the tc can be used as valid bit,
-- in the memory we can use the E2M_tc and in the wb we can use M2WB_tc, because the terminal count is always set when
-- the instruction leaves the execute unit. This tc signal has to be produced by the FSM.

-- TODO: create a control signal which specifies the kind of instruction (R,I,J).
-- This makes it much easier to detect hazards, because you know directly which bits in the instruction you have to check.
entity CU is
  port(
    clk: in std_logic;
    rst: in std_logic; --asynch
    branch_outcome: in std_logic; -- Outcome Branch predictor
    opcode: in  std_logic_vector(5 downto 0);
	DEC2_ALU_unit: in std_logic_vector(4 downto 0); -- the ALU unit where the instruction in DEC2 will be executed

    funct: in std_logic_vector(10 downto 0);

    ALU_op: out std_logic_vector(4 downto 0);
	ALU_unit: out std_logic_vector(4 downto 0); -- one hot encoding representation of the ALU unit where the operation will be performed
    OpA_sel: out std_logic;
    OpB_sel: out std_logic;
    beqz_or_bnez: out std_logic; -- TODO: use it in a xor operation
    is_branch: out std_logic; -- Is the comparison for a (conditional) branch?
	is_uncond_branch: out std_logic; -- Unconditional branch signaling
    rw_dmem: out std_logic; 
    res_sel: out std_logic_vector(1 downto 0); -- To select ALU or Memory read data
    w_reg: out std_logic;
    dest_sel: out std_logic_vector(1 downto 0); -- To select the register inside the RF
	-- Pipeline registers enable
    F2D_en: out std_logic;
    F2D_clr: out std_logic;
    D2E_clr: out std_logic;
    E2M_clr: out std_logic;
    M2WB_clr: out std_logic;
	RIJ: out std_logic_vector(1 downto 0); -- to determine the kind of instruction (R,I or J)
	ROB_full: in std_logic; -- set to 1 if the ROB is full (considering also the instruction currently in decode and the one going in writeback)
	haz_neg: in std_logic; -- set to 1 if the operands for the instruction in decode are ready, so there is no need to stall
	RS_full: in std_logic; -- 1 if the RS are full

	-- busy signals for the ALU units
	add_busy: in std_logic;
	shifter_busy: in std_logic;
	logicals_busy: in std_logic;
	div_busy: in std_logic;
	mul_busy: in std_logic;

	-- the ROB entry to be committed
	dec_ready: out std_logic
    );
end CU;

architecture behavioral of CU is

type StateT is (operate, stall);
signal stateNext,stateCurr: StateT;
-- OPS MUST NOT BE 00000, THIS VALUE IS CONSIDERED AS A NOP ACCORDING TO THE PIPELINE FUNCTIONING
-- find the best values to optimize the checks performed with comparators in the ALU
-- these ops are inteded to be used as ALUops
signal ALU_op_int: std_logic_vector(4 downto 0);
signal ALU_unit_int: std_logic_vector(4 downto 0);
signal curr_rob_entry: std_logic_vector(5 downto 0);
signal next_rob_entry: std_logic_vector(5 downto 0);
signal commit_int: std_logic;

begin

	ALU_op <= ALU_op_int;
	ALU_unit <= ALU_unit_int;

	process(stateCurr, branch_outcome, opcode, funct, ROB_full, haz_neg, add_busy, logicals_busy, shifter_busy, mul_busy, div_busy, ALU_OP_int, rs_full) 
		variable instruction_in_dec_not_able_to_leave : std_logic := '0';
		variable hazard_thrown_rob: std_logic := '0';
		variable hazard_thrown_rs: std_logic := '0';
		variable hazard_thrown_add : std_logic := '0';
		variable hazard_thrown_shifter : std_logic := '0';
		variable hazard_thrown_logicals: std_logic := '0';
		variable hazard_thrown_mul: std_logic := '0';
		variable hazard_thrown_div: std_logic := '0';
	begin
		dec_ready <= '1';
		-- activate all the pipeline registers, so that they are able to store results from each stage
		F2D_en<='1';
		F2D_clr<='0';
		D2E_clr<='0';
		E2M_clr<='0';
		M2WB_clr<='0';
		-- generate control signals depending on the opcode
		ALU_op_int<=(others=>'0');
		ALU_unit_int<=(others=>'0');
		OpA_sel<='0';
		OpB_sel<='0';
		beqz_or_bnez<='0';
		is_branch<='0';
		rw_dmem<='0';
		res_sel<="00";
		w_reg<='0';
		dest_sel<="00";
		is_uncond_branch<='0';
		RIJ<="00"; -- default to R type
		case opcode is
			when "000000" =>
				case funct is
					when "00000000000" => --nop
					when "00000000001" => --add
						ALU_unit_int(0)<='1';
						ALU_op_int<=ADD_OP;
						res_sel<="01";
						w_reg<='1';
						dest_sel<="00"; -- it selects reg 3
					when "00000000011" => --and
						ALU_unit_int(1)<='1';
						ALU_op_int<=AND_OP;
						res_sel<="01";
						w_reg<='1';
						dest_sel<="00";
					when "00000001010" => --or
						ALU_unit_int(1)<='1';
						ALU_op_int<=OR_OP;
						res_sel<="01";
						w_reg<='1';
						dest_sel<="00";
					when "00000001100" => --sge
						ALU_unit_int(0)<='1';
						ALU_op_int<=SGE_OP;
						res_sel<="01";
						w_reg<='1';
						dest_sel<="00";
					when "00000010000" => --sle
						ALU_unit_int(0)<='1';
						ALU_op_int<=SLE_OP;
						res_sel<="01";
						w_reg<='1';
						dest_sel<="00";
					when "00000010010" => --sll
						ALU_unit_int(2)<='1';
						ALU_op_int<=SLL_OP;
						res_sel<="01";
						w_reg<='1';
						dest_sel<="00";
					when "00000010101" => --sne
						ALU_unit_int(0)<='1';
						ALU_op_int<=SNE_OP;
						res_sel<="01";
						w_reg<='1';
						dest_sel<="00";
					when "00000010111" => --srl
						ALU_unit_int(2)<='1';
						ALU_op_int<=SRL_OP;
						res_sel<="01";
						w_reg<='1';
						dest_sel<="00";
					when "00000011000" => --mul
						ALU_unit_int(3)<='1';
						ALU_op_int<=MUL_OP;
						res_sel<="01";
						w_reg<='1';
						dest_sel<="00";
					when "00000011001" => --div
						ALU_unit_int(4)<='1';
						ALU_op_int<=DIV_OP;
						res_sel<="01";
						w_reg<='1';
						dest_sel<="00";
					when "00000011010" => --sub
						ALU_unit_int(0)<='1';
						ALU_op_int<=SUB_OP;
						res_sel<="01";
						w_reg<='1';
						dest_sel<="00";
					when "00000011011" => --xor
						ALU_unit_int(1)<='1';
						ALU_op_int<=XOR_OP;
						res_sel<="01";
						w_reg<='1';
						dest_sel<="00";
					when others => -- other opcodes are considered as nops
				end case;
			when "000001" =>
			when "000010" => -- addi
				ALU_unit_int(0)<='1';
				ALU_op_int<=ADD_OP;
				RIJ<="01"; -- I type
				OpB_sel<='1';
				res_sel<="01";
				w_reg<='1';
				dest_sel<="01"; --regB
			when "000011" =>
			when "000100" => --andi
				ALU_unit_int(1)<='1';
				RIJ<="01"; -- I type
				ALU_op_int<=AND_OP;
				OpB_sel<='1';
				res_sel<="01";
				w_reg<='1';
				dest_sel<="01";
			when "000101" => --beqz
				ALU_unit_int(0)<='1';
				RIJ<="01"; -- I type
				ALU_op_int<=ADD_OP;
				OpA_sel<='1'; -- select the PC+4
				OpB_sel<='1';
				beqz_or_bnez<='0'; --beqz
				is_branch<='1';
				res_sel<="01";
			when "000110" =>
			when "000111" =>
			when "001000" => --bnez
				ALU_unit_int(0)<='1';
				RIJ<="01"; -- I type
				ALU_op_int<=ADD_OP;
				OpA_sel<='1';
				OpB_sel<='1';
				beqz_or_bnez<='1'; -- bnez
				is_branch<='1';
				res_sel<="01";
			when "001001" => --j
				ALU_unit_int(0)<='1';
				RIJ<="10"; -- J type
				ALU_op_int<=ADD_OP;
				OpA_sel<='1';
				OpB_sel<='1';
				is_branch<='1';
				is_uncond_branch<='1';
				res_sel<="01";
			when "001010" => --jal
				ALU_unit_int(0)<='1';
				RIJ<="10"; -- J type
				ALU_op_int<=ADD_OP;
				OpA_sel<='1';
				OpB_sel<='1';
				res_sel<="10"; --PC+8
				is_branch<='1';
				is_uncond_branch<='1';
				dest_sel<="10";
				w_reg <= '1';
			when "001011" =>
			when "001100" =>
			when "001101" =>
			when "001110" =>
			when "001111" =>
			when "010100" => --lw
				ALU_unit_int(0)<='1';
				RIJ<="01"; -- I type
				ALU_op_int<=ADD_OP;
				OpA_sel<='0';
				OpB_sel<='1';
				res_sel<="00";
				dest_sel<="01"; --regB
				w_reg<='1';
			when "010101" => --ori
				ALU_unit_int(1)<='1';
				RIJ<="01"; -- I type
				ALU_op_int<=OR_OP;
				OpB_sel<='1';
				res_sel<="01";
				w_reg<='1';
				dest_sel<="01";
			when "011011" => --sgei
				ALU_unit_int(0)<='1';
				RIJ<="01"; -- I type
				ALU_op_int<=SGE_OP;
				OpB_sel<='1';
				res_sel<="01";
				w_reg<='1';
				dest_sel<="01";
			when "100000" => --slei
				ALU_unit_int(0)<='1';
				RIJ<="01"; -- I type
				ALU_op_int<=SLE_OP;
				OpB_sel<='1';
				res_sel<="01";
				w_reg<='1';
				dest_sel<="01";
			when "100010" => --slli
				ALU_unit_int(0)<='1';
				RIJ<="01"; -- I type
				ALU_op_int<=SLL_OP;
				OpB_sel<='1';
				res_sel<="01";
				w_reg<='1';
				dest_sel<="01";
			when "100101" => --snei
				ALU_unit_int(0)<='1';
				RIJ<="01"; -- I type
				ALU_op_int<=SNE_OP;
				OpB_sel<='1';
				res_sel<="01";
				w_reg<='1';
				dest_sel<="01";
			when "100111" => --srli
				ALU_unit_int(2)<='1';
				RIJ<="01"; -- I type
				ALU_op_int<=SRL_OP;
				OpB_sel<='1';
				res_sel<="01";
				w_reg<='1';
				dest_sel<="01";
			when "101000" => --subi
				ALU_unit_int(0)<='1';
				RIJ<="01"; -- I type
				ALU_op_int<=SUB_OP;
				OpB_sel<='1';
				res_sel<="01";
				w_reg<='1';
				dest_sel<="01";
			when "101010" => --sw
				ALU_unit_int(0)<='1';
				ALU_op_int<=ADD_OP;
				RIJ<="01"; -- I type
				OpB_sel<='1';
				rw_dmem<='1';
				res_sel<="01";
			when "101100" => --xori
				ALU_unit_int(1)<='1';
				RIJ<="01"; -- I type
				ALU_op_int<=XOR_OP;
				OpB_sel<='1';
				res_sel<="01";
				w_reg<='1';
				dest_sel<="01";
			when others =>
		end case;
		instruction_in_dec_not_able_to_leave := '0';
		hazard_thrown_rob := '0';
		hazard_thrown_add := '0';
		hazard_thrown_shifter := '0';
		hazard_thrown_logicals := '0';
		hazard_thrown_mul := '0';
		hazard_thrown_div := '0';
		hazard_thrown_rs := '0';
		if(DEC2_ALU_unit(0)='1' and add_busy='1') then
			hazard_thrown_add := '1';
		end if;
		if(DEC2_ALU_unit(1)='1' and logicals_busy='1') then
			hazard_thrown_logicals := '1';
		end if;
		if(DEC2_ALU_unit(2)='1' and shifter_busy='1') then
			hazard_thrown_shifter := '1';
		end if;
		if(DEC2_ALU_unit(3)='1' and mul_busy='1') then
			hazard_thrown_mul := '1';
		end if;
		if(DEC2_ALU_unit(4)='1' and div_busy='1') then
			hazard_thrown_div := '1';
		end if;
		-- haz_neg will never be zero with a nop, so the pipeline can't stall
		if(haz_neg='0' or hazard_thrown_add = '1' or hazard_thrown_shifter = '1' or  hazard_thrown_logicals = '1' or hazard_thrown_mul = '1' or hazard_thrown_div = '1') then
			instruction_in_dec_not_able_to_leave := '1';
			dec_ready <= not instruction_in_dec_not_able_to_leave;
		end if;
		-- second kind of hazard: the instruction which is currently in decode is the one that occupies the last free space in the ROB + no valid writeback
		-- these last conditions are checked inside the datapath, which produces a ROB_full signal when they are verified
		if(ROB_full='1') then -- TODO: FIX THE CASE IN WHICH THE ROB IS FULL AT THE BEGINNING AND YOU HAVE TO ALLOCATE AFTERWARD.
			hazard_thrown_rob := '1';
		end if;
		-- if no instruction can leave or if the rob/rs are full you have to stall the F2D
		if(hazard_thrown_rob = '1') then
			F2D_en <= '0';
		end if;
		-- branch outcome is driven from the decode stage when the commit of the branch is performed
		if(branch_outcome='1') then -- taken branch in the memory stage (misprediction)
			F2D_en<='0'; -- resetting the F2D_en is needed to avoid allocation of a new instruction in the cycles when the pipeline is refilling
			F2D_clr<='1'; -- it is needed to send the clear to distinguish between the case in which you stall for an hazard and the one in which you need to clear for a misprediction
			D2E_clr<='1'; -- this signal has to be used for all the internal registers in the EXE
			E2M_clr<='1'; -- needed to block instruction in the middle of the pipeline
			M2WB_clr<='1'; -- needed to block instruction in the middle of the pipeline
			stateNext<=operate;
		end if;
	end process;

end behavioral;

configuration CFG_CU of CU is
    for behavioral
    end for;
end configuration;