-- cpu.vhd: Simple 8-bit CPU (BrainFuck interpreter)
-- Copyright (C) 2022 Brno University of Technology,
--                    Faculty of Information Technology
-- Author(s): Erik Hrubý <xhruby30 AT stud.fit.vutbr.cz>
--
library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_arith.all;
use ieee.std_logic_unsigned.all;

-- ----------------------------------------------------------------------------
--                        Entity declaration
-- ----------------------------------------------------------------------------
entity cpu is
 port (
   CLK   : in std_logic;  -- hodinovy signal
   RESET : in std_logic;  -- asynchronni reset procesoru
   EN    : in std_logic;  -- povoleni cinnosti procesoru
 
   -- synchronni pamet RAM
   DATA_ADDR  : out std_logic_vector(12 downto 0); -- adresa do pameti
   DATA_WDATA : out std_logic_vector(7 downto 0); -- mem[DATA_ADDR] <- DATA_WDATA pokud DATA_EN='1'
   DATA_RDATA : in std_logic_vector(7 downto 0);  -- DATA_RDATA <- ram[DATA_ADDR] pokud DATA_EN='1'
   DATA_RDWR  : out std_logic;                    -- cteni (0) / zapis (1)
   DATA_EN    : out std_logic;                    -- povoleni cinnosti
   
   -- vstupni port
   IN_DATA   : in std_logic_vector(7 downto 0);   -- IN_DATA <- stav klavesnice pokud IN_VLD='1' a IN_REQ='1'
   IN_VLD    : in std_logic;                      -- data platna
   IN_REQ    : out std_logic;                     -- pozadavek na vstup data
   
   -- vystupni port
   OUT_DATA : out  std_logic_vector(7 downto 0);  -- zapisovana data
   OUT_BUSY : in std_logic;                       -- LCD je zaneprazdnen (1), nelze zapisovat
   OUT_WE   : out std_logic                       -- LCD <- OUT_DATA pokud OUT_WE='1' a OUT_BUSY='0'
 );
end cpu;

-- ----------------------------------------------------------------------------
--                      Architecture declaration
-- ----------------------------------------------------------------------------
architecture behavioral of cpu is
  signal PC      : std_logic_vector(12 downto 0);
  signal PC_INC  : std_logic;
  signal PC_DEC  : std_logic;

  signal PTR     : std_logic_vector(12 downto 0);
  signal PTR_INC : std_logic;
  signal PTR_DEC : std_logic;

  signal CNT     : std_logic_vector(7 downto 0); -- s predpokladom ze 256 zanoreni bude stacit
  signal CNT_INC : std_logic;
  signal CNT_DEC : std_logic;


  signal MX1_SEL : std_logic;
  signal MX2_SEL : std_logic_vector(1 downto 0);
  
  type fsm_state is ( idle, halt, fetch0, fetch1, decode, 
                      incvalue0, incvalue1, decvalue0, decvalue1, 
                      incptr, decptr, 
                      print0, print1, print2, printwait,
                      read0, read1, readwait, 
                      whilebegin, whilebegin1, while1, while2, while3, while4, while5,
                      whileend, whileend0, whileend1, whileend2, whileend3, whileend4, whileend5, whileend6);
  signal PSTATE  : fsm_state;
  signal NSTATE  : fsm_state;
begin

  pc_reg: process (RESET, CLK)
  begin
    if (RESET = '1') then 
    PC <= (others => '0');
    elsif (CLK'event) and (CLK='1') then
      if (PC_INC = '1') then
        PC <= PC + 1;
      elsif (PC_DEC = '1') then
        PC <= PC - 1;
      end if;
    end if;
  end process;

  ptr_reg: process (RESET, CLK)
  begin
    if (RESET = '1') then
      PTR <= "1000000000000";            -- 0x1000 address
    elsif (CLK'event) and (CLK='1') then 

      if (PTR_INC = '1') then      
        if (PTR = "1111111111111") then  -- 0x1FFF address
          PTR <= "1000000000000";        -- 0x1000 address
        else
          PTR <= PTR + 1;
        end if;
        
      elsif (PTR_DEC = '1') then
        if (PTR = "1000000000000") then  -- 0x1000 address
          PTR <= "1111111111111";        -- 0x1FFF address
        else
          PTR <= PTR - 1;
        end if;
        
      end if;            
    end if;
  end process;

  cnt_reg: process (RESET, CLK)
  begin
    if (RESET = '1') then 
    CNT <= (others => '0');
    elsif (CLK'event) and (CLK='1') then
      if (CNT_INC = '1') then
        CNT <= CNT + 1;
      elsif (CNT_DEC = '1') then
        CNT <= CNT - 1;
      end if;
    end if;
  end process;


  DATA_ADDR  <= PC             when (MX1_SEL = '0')  else PTR; -- MX1

  DATA_WDATA <= IN_DATA        when (MX2_SEL = "00") else      -- MX2
                DATA_RDATA - 1 when (MX2_SEL = "01") else
                DATA_RDATA + 1 when (MX2_SEL = "10") else
                DATA_RDATA;



  fsm_pstate: process (RESET, CLK, EN)
  begin
    if (RESET = '1') then
      PSTATE <= idle;    
    elsif (CLK'event) and (CLK='1') then
      if (EN = '1') then
        PSTATE <= NSTATE;
      end if;
    end if;
  end process;

  fsm_nstate: process (PSTATE)
  begin 
    ------------ INIT ----------------

    -- RAM
    DATA_EN <= '0';
    DATA_RDWR <= '0';

    -- I/O
    IN_REQ <= '0';
    OUT_WE <= '0';

    -- REGISTERS
    PC_INC <= '0';
    PC_DEC <= '0';
    PTR_INC <= '0';
    PTR_DEC <= '0';
    CNT_INC <= '0';
    CNT_DEC <= '0';

    -- MULTIPLEXORS
    MX1_SEL <= '0';
    MX2_SEL <= "00";
    ------------------------------------
    case PSTATE is    
      when idle =>
        NSTATE <= fetch0;
        
      when halt =>
        NSTATE <= halt;

      when fetch0 =>
        NSTATE <= fetch1;
        DATA_EN <= '1';

      when fetch1 => 
        NSTATE <= decode;        
        PC_INC <= '1';

      ------- decode instruction ---------
      when decode =>  
        case DATA_RDATA is
          when X"3E" =>
            NSTATE <= incptr;

          when X"3C" =>
            NSTATE <= decptr;

          when X"2B" =>     
            NSTATE <= incvalue0;

          when X"2D" =>
            NSTATE <= decvalue0;
            
          when X"5B" =>
           NSTATE <= whilebegin;

          when X"5D" =>
           NSTATE <= whileend;
          
          when X"2E" =>
            NSTATE <= print0;

          when X"2C" =>
            NSTATE <= read0;

          when X"00" => 
            NSTATE <= halt;

          when others => 
            NSTATE <= fetch0;
        end case;        
      ------------------------------------

      when incvalue0 =>
        NSTATE <= incvalue1;
        MX1_SEL <= '1';
        DATA_EN <= '1';
      
      when incvalue1 =>
        NSTATE <= fetch0;
        MX2_SEL <= "10";
        MX1_SEL <= '1';
        DATA_EN <= '1';
        DATA_RDWR <= '1';
      
      when decvalue0 =>
        NSTATE <= decvalue1;
        MX1_SEL <= '1';
        DATA_EN <= '1';

      when decvalue1 =>
        NSTATE <= fetch0;
        MX2_SEL <= "01";
        MX1_SEL <= '1';
        DATA_EN <= '1';
        DATA_RDWR <= '1';
      
      when incptr =>
        NSTATE <= fetch0;
        PTR_INC <= '1';
      
      when decptr =>
        NSTATE <= fetch0;
        PTR_DEC <= '1';

      when print0 =>
        NSTATE <= print1;
        MX1_SEL <= '1';
        DATA_EN <= '1';
      
      when print1 =>
        NSTATE <= print2;        

      when print2 =>
        if (OUT_BUSY = '0') then
          NSTATE <= fetch0;
          OUT_DATA <= DATA_RDATA;          
          OUT_WE <= '1';
        else
          NSTATE <= printwait;
        end if;          

      when printwait =>
        NSTATE <= print2;

      when read0 =>
        NSTATE <= read1;
        IN_REQ <= '1';                                        
      
      when read1 => 
        if (IN_VLD = '1') then
          NSTATE <= fetch0;
          MX2_SEL <= "00";
          MX1_SEL <= '1';
          DATA_EN <= '1';
          DATA_RDWR <= '1';
        else
          IN_REQ <= '1';
          NSTATE <= readwait;
        end if;        
      
      when readwait =>
        if (IN_VLD = '1') then
          NSTATE <= fetch0;
          MX2_SEL <= "00";
          MX1_SEL <= '1';
          DATA_EN <= '1';
          DATA_RDWR <= '1';
        else
          IN_REQ <= '1';
          NSTATE <= read1;
        end if;
        
      when whilebegin =>
        NSTATE <= whilebegin1;
        MX1_SEL <= '1';
        DATA_EN <= '1';
      
      when whilebegin1 =>
        NSTATE <= while1;
      
      when while1 =>
        if (DATA_RDATA = "00000000") then
          NSTATE <= while2;          
          CNT_INC <= '1';
          DATA_EN <= '1';
        else
          NSTATE <= fetch0;
        end if;

      when while4 =>
        NSTATE <= while2;
        DATA_EN <= '1';

      when while2 =>
        NSTATE <= while3;

      when while3 =>
        NSTATE <= while5;
        if (DATA_RDATA = X"5B") then          
          CNT_INC <= '1';
        elsif (DATA_RDATA = X"5D") then
          CNT_DEC <= '1';
        else
          NSTATE <= while4;
          PC_INC <= '1';
        end if;

      when while5 =>
        if (CNT = "00000000") then
          NSTATE <= fetch0;
          PC_INC <= '1';            
        else 
          NSTATE <= while4;
          PC_INC <= '1';
        end if;
      
      when whileend =>
        NSTATE <= whileend0;
        MX1_SEL <= '1';
        DATA_EN <= '1';

      when whileend0 =>
        NSTATE <= whileend1;

      when whileend1 =>
        if (DATA_RDATA = "00000000") then
          NSTATE <= fetch0;
        else
          NSTATE <= whileend2;
          CNT_INC <= '1';
          PC_DEC <= '1';
        end if;
      
        when whileend2 =>
          NSTATE <= whileend3;
          PC_DEC <= '1';

        when whileend3 =>
          NSTATE <= whileend4;
          DATA_EN <= '1';
        
        when whileend4 =>
          NSTATE <= whileend5;

        when whileend5 =>
          NSTATE <= whileend6;
          if (DATA_RDATA = X"5D") then          
            CNT_INC <= '1';
          elsif (DATA_RDATA = X"5B") then
            CNT_DEC <= '1';
          else
            NSTATE <= whileend3;
            PC_DEC <= '1';
          end if;

        when whileend6 =>
          if (CNT = "00000000") then
            NSTATE <= fetch0;            
          else 
            NSTATE <= whileend3;
            PC_DEC <= '1';
          end if;

    end case;
  end process;      
end behavioral;

