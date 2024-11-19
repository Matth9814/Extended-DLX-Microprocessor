library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.std_logic_unsigned.all;
use work.constants.all;
use IEEE.math_real.all;

entity CARRY_GENERATOR is
  generic (NBIT: natural := numBitP4; -- radix of the carry generator
           NBLKS: natural := numBlocksP4); -- number of carry select blocks (thus the number of carries to be produced)
  port(A,B: in std_logic_vector((NBIT*NBLKS)-1 downto 0);
       Cin: in std_logic;
       Cout: out std_logic_vector(NBLKS-1 downto 0));
end CARRY_GENERATOR;

architecture STRUCTURE of CARRY_GENERATOR is

  component G is
      port(Pik,Gik,Gkj: in std_logic;
           Gij: out std_logic);
  end component;

  component PG is
      port(Pik,Pkj,Gik,Gkj: in std_logic;
           Gij,Pij: out std_logic);
  end component;
  
  -- the component which represents the blocks in the PG net, which have to generate p and g
  component PG_elem_net is
  port(a,b: in std_logic;
       p,g: out std_logic);
  end component;
    
  -- Total number of bits
  constant NTOT: natural := NBIT*NBLKS;
  -- Number of rows of the sparse tree
  constant ROWS: natural := natural(log2(real(NTOT))); 

  -- P and G signals matrix: we assume a number of elements for each row equal to the number of bits of the inputs
  -- this corresponds to the worst case size of a row (in the first row we have to generate NTOT p and NTOT g)
  type sigMatrix is array (0 to ROWS) of std_logic_vector(NTOT-1 downto 0);
  signal gm: sigMatrix;
  signal pm: sigMatrix;
  signal p1,g1: std_logic;

  function binary_search (k: natural; n: natural) return natural is
    -- to determine the height of the "ladder" which gives the connections between additional blocks and other blocks in point k
    -- k horizontal position in the ladder from the left, n horizontal length of the ladder
    variable interval_pos: natural;
    variable return_value: natural;
    variable over: natural;
    begin
    -- we start positioning at the left extreme of the interval
    interval_pos :=0;
    over :=0;
    return_value:=natural(log2(real(n)))+1;
    for i in 0 to natural(log2(real(NTOT/NBIT))) loop 
    -- the max horizontal length of the ladder is given by log2(real(NTOT/NBIT))
      if (k < n/(2**(i+1))+interval_pos and over/=1) then 
      -- if k belongs to the interval on the left we have to stop, because we know that all the elements in the left interval have the same height
      -- which is given by (i+1)
        return_value:=(i+1);
        over:=1;
      end if;
      -- we go in a position in the interval which corresponds to the current pos + n divided by the next power of two
      -- for example: at the beginning we place in 0, then in n/2, then in 3*n/4, then 7*n/8 ...
      -- in this way we are doing a kind of dicotomic search, but we move only to the right (because all the nodes
      -- in the left half have the same height with respect to the bottom)
      interval_pos:=interval_pos+n/(2**(i+1));
    end loop;
    return return_value;
  end binary_search;

  
begin
  -- first row: the one corresponding to the PG net.
  -- for this row we need blocks of type PG_elem_net and G
  CGrow: for i in 0 to ROWS generate
    Row0: if(i=0) generate
      to_gen_row_1: for j in 0 to (NTOT-1) generate
        -- in the first column (the one which receives A(0),B(0) and Cin) we have a PG_elem_net
        -- and a G block cascaded
        pg_G: if (j=0) generate
          pg0: PG_elem_net port map(a=>A(0),b=>B(0),p=>p1,g=>g1);
          G0: G port map(Pik=>p1,Gik=>g1,Gkj=>Cin,Gij=>gm(i)(j));
        end generate;
        -- for the other columns we need only a PG_elem_net
        pg_others: if(j>0) generate
          pg_elem: PG_elem_net port map(a=>A(j),b=>B(j),p=>pm(i)(j),g=>gm(i)(j));
        end generate;
      end generate;
    end generate;
    
    Row_1toLast: if(i/=0) generate
      to_gen_row_n: for j in 0 to NTOT-1 generate  -- Row_1:ROWS generation
        -- First G block starting from left
        -- we divide G and PG blocks in two type: regular and additional. The regular blocks are the ones that we would have if we had
        -- a regular binary tree with the root at the bottom : to make the definition clear, let's imagine that the leaves of this regular tree
        -- are the elements of the PG net and the root is given by the G block which generates C(32) in the last row.
        -- The additional elements are all the G and PG blocks that are not part of this regular tree. In order to insert both 
        -- the types of blocks we have to properly parameterize them : the regular blocks are very simple to parameterize, while for the additional
        -- ones we verified that they are present on every row in a number that is given by ((2**(i-1))/NBIT)-2 (this number is 0 for the first 3 rows,
        -- where the additional blocks are not present). A critical point regarding the additional blocks is given by the fact that the connections to
        -- blocks in the previous lines are such that they can be fed with inputs that come from different rows, not only the previous one.
        -- We parameterized these connections through the binary_search() function.
        to_gen_regular_G: if(j=((2**i)-1)) generate  
          Gn: G port map(Pik=>pm(i-1)((2**i)-1),Gik=>gm(i-1)((2**i)-1),Gkj=>gm(i-1)((2**(i-1))-1),Gij=>gm(i)((2**i)-1));
          -- Additional G blocks after the first one starting from the left
          to_gen_add_G: for k in 0 to ((2**(i-1))/NBIT)-2 generate
            Gn_plus: G port map(Pik=>pm(i-binary_search(k+1,((2**(i-1))/NBIT)))((2**i)-1-NBIT*(k+1)),Gik=>gm(i-binary_search(k+1,((2**(i-1))/NBIT)))((2**i)-1-NBIT*(k+1)),Gkj=>gm(i-1)((2**(i-1)-1)),Gij=>gm(i)((2**i)-1-NBIT*(k+1)));
          end generate;
        end generate;
        --PG blocks generated with a regular step
        to_gen_regular_PG: if((j mod (2**i))=(2**i-1) and j/=2**i-1) generate
          PGn: PG port map(Pik=>pm(i-1)(j),Pkj=>pm(i-1)(j-2**(i-1)),Gik=>gm(i-1)(j),Gkj=>gm(i-1)(j-2**(i-1)),Gij=>gm(i)(j),Pij=>pm(i)(j));
          -- PG blocks generated to the right, near the regular ones
          -- This happens starting from the 4th row of the sparse tree (for the first 3 rows the for loop is from 0 to 0, so it is not executed)
          to_gen_add_PG: for k in 0 to ((2**(i-1))/NBIT)-2 generate
            PGn_plus: PG port map(Pik=>pm(i-binary_search(k+1,((2**(i-1))/NBIT)))(j-NBIT*(k+1)),Pkj=>pm(i-1)(j-2**(i-1)),Gik=>gm(i-binary_search(k+1,((2**(i-1))/NBIT)))(j-NBIT*(k+1)),Gkj=>gm(i-1)(j-2**(i-1)),Gij=>gm(i)(j-NBIT*(k+1)),Pij=>pm(i)(j-NBIT*(k+1)));
          end generate;
        end generate;
      end generate;
    end generate;
  end generate;
  -- it is necessary to map the carries to precise entries in the PG matrix
  -- if we take a look at how the carries are connected to the blocks, we find out that
  -- the mechanism is the same that regulates the placement and connection of additional blocks.
  carry_mapping: for i in 0 to NTOT/NBIT-1 generate 
  --to map the carries to specific entries in the matrixes
    Cout(NTOT/NBIT-i-1)<=gm(ROWS-binary_search(i,NTOT/NBIT)+1)(NTOT-1-i*NBIT);
  end generate;
end STRUCTURE;

configuration CFG_CG_STRUCTURAL of CARRY_GENERATOR is
  for STRUCTURE
  end for;
end CFG_CG_STRUCTURAL;
