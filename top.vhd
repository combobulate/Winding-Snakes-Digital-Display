-- Logic for a two-sided seven-segment display such as the Digilent PmodSSD, to show a three-
-- segment snakelike winding through the segments on both sides at slightly different rates
-- to give a random, racing appearance. Could be used for a loading/processing visual display.
--
-- This code uses logic and design from the VHDLWhiz "Hands-on for absolute beginners" fast-
-- track course:
--       https://academy.vhdlwhiz.com/fast-track
-- This (highly recommended) course walks students through programming an FPGA to display a
-- counter incrementing from 00 through 99 every second. The design and logic for the
-- snakelike winding are my own contribution.
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity top is
  generic(
    -- Clock speed for Lattice iCEstick Evaluation Kit
    clk_hz          : integer := 12e6;
    alt_counter_len : integer := 16
  );
  port (
    clk       : in std_logic;
    rst_n     : in std_logic;
    segments  : out std_logic_vector(6 downto 0);
    digit_sel : out std_logic
  );
end top;

architecture rtl of top is

  -- Internal reset
  signal rst : std_logic;

  -- Shift register for generating the internal reset
  signal shift_reg : std_logic_vector(7 downto 0);

  -- For timing the snaking segment changes. Every clock cycle the tick_counter increments up
  -- to tick_counter_max. Each time that value is reached (400 times a second), tick is set to
  -- high, enabling the logic to check if either snake segment changes, set below.
  constant tick_counter_max : integer := clk_hz/400 - 1;
  signal tick_counter       : integer range 0 to tick_counter_max;
  signal tick               : std_logic;

  -- Snake segment logic. There are two "snakes" traversing each of the two 7-segment digits on
  -- the display. Each time tick is set to high, snake_counter is incremented, and the modulus
  -- is taken with respect to the two _mod constants to see which of the two segments is updated.
  -- The nearby values of these mods makes these snakes move at what visually seems to be about
  -- the same rate, but slightly offset from each other in a way that appears random and racing.
  -- The chosen constants mean that snake0 changes 400/48 = 8 1/3 times a second, and snake1
  -- changes 400/40 = 10 times a second. snake_counter_max is the least common multiple of these
  -- mods.
  constant snake0_mod         : integer := 48;
  constant snake1_mod         : integer := 40;
  constant snake_counter_max  : integer := 240 - 1;
  signal snake_counter        : integer range 0 to snake_counter_max;
  subtype snake_type          is integer range 0 to 33;
  signal snake                : snake_type;
  type snakes_type            is array (0 to 1) of snake_type;
  signal snakes               : snakes_type;
  
  -- 16 bit counter for alternating between sides of the display. 12e6/(2**16) = 183.1 Hz
  -- refresh rate for illuminating each digit.
  signal alt_counter : unsigned(alt_counter_len - 1 downto 0);

  -- incr_wrap: iterates through the input snake signal, which goes through a sequence of 34 frames.
  -- Modified from VHDLWhiz tutorial.
  procedure incr_wrap(signal s : inout snake_type) is
  begin
    if s = 33 then
      s <= 0;
    else
      s <= s + 1;
    end if;
  end procedure;

begin

  -- SNAKE_TICK_PROC: for each high value on tick, checks if the current snake_counter is divisible
  -- by the preset mod values for each snake signal, increments accordingly, and increments the
  -- snake_counter.
  SNAKE_TICK_PROC : process(clk)
  begin
    if rising_edge(clk) then
      if rst = '1' then
        snakes <= (others => 0);
        snake_counter <= 0;
        
      else
        if tick = '1' then
          if snake_counter MOD snake0_mod = 0 then
            incr_wrap(snakes(0));
          end if;

          if snake_counter MOD snake1_mod = 0 then
            incr_wrap(snakes(1));
          end if;

          if snake_counter = snake_counter_max then
            snake_counter <= 0;
          else
            snake_counter <= snake_counter + 1;
          end if;
        end if;

      end if;
    end if;
  end process;

  -- ALTERNATE_COUNTER_PROC: counts through alt_counter to create a periodic high signal, used by
  -- OUTPUT_MUX_PROC to alternate which side of the display is lit. From VHDLWhiz tutorial.
  ALTERNATE_COUNTER_PROC : process(clk)
  begin
    if rising_edge(clk) then
      if rst = '1' then
        alt_counter <= (others => '0');
        
      else
        alt_counter <= alt_counter + 1;
        
      end if;
    end if;
  end process;

  -- OUTPUT_MUX_PROC: uses alt_counter to alternate which side of the display is lit. Modified
  -- from VHDLWhiz tutorial.
  OUTPUT_MUX_PROC : process(alt_counter)
  begin
    if alt_counter(alt_counter'high) = '1' then
      snake <= snakes(1);
      digit_sel <= '1';
    else
      snake <= snakes(0);
      digit_sel <= '0';
    end if;
  end process;

  -- TICK_PROC: uses clk to periodically set tick to high, to control timing of events. From
  -- VHDLWhiz tutorial.
  TICK_PROC : process(clk)
  begin
    if rising_edge(clk) then
      if rst = '1' then
        tick_counter <= 0;
        tick <= '0';
        
      else
        if tick_counter = tick_counter_max then
          tick_counter <= 0;
          tick <= '1';
        else
          tick_counter <= tick_counter + 1;
          tick <= '0';
        end if;
        
      end if;
    end if;
  end process;

  -- SHIFT_REG_PROC: uses clk to pass bits into an array, used by RESET_PROC to flip rst to low
  -- and enable standard display behavior. From VHDLWhiz tutorial. 
  SHIFT_REG_PROC : process(clk)
  begin
    if rising_edge(clk) then
      shift_reg <= shift_reg(6 downto 0) & rst_n;
    end if;
  end process;

  -- RESET_PROC: uses shift_reg array to determine when to turn rst high or low. From VHDLWhiz
  -- tutorial.
  RESET_PROC : process(shift_reg)
  begin
    if shift_reg = "11111111" then
      rst <= '0';
    else
      rst <= '1';
    end if;
  end process;

  -- ENCODER_PROC: encodes the snake signal. This encoding has a sequence of 34 frames, with only
  -- 14 distinct combinations of segments across those frames.  
  ENCODER_PROC : process(snake)
    -- Segments from the PMOD SSD datasheet
    constant A : integer := 0; 
    constant B : integer := 1; 
    constant C : integer := 2; 
    constant D : integer := 3; 
    constant E : integer := 4; 
    constant F : integer := 5; 
    constant G : integer := 6; 

  begin

    segments <= (others => '0');

    case snake is
      
      when 0 | 8 | 14 | 21 | 28 =>
        segments(A) <= '1';
        segments(B) <= '1';
        segments(F) <= '1';

      when 1 | 20 =>
        segments(A) <= '1';
        segments(B) <= '1';
        segments(G) <= '1';

      when 2 | 19 =>
        segments(B) <= '1';
        segments(E) <= '1';
        segments(G) <= '1';

      when 3 | 18 =>
        segments(D) <= '1';
        segments(E) <= '1';
        segments(G) <= '1';

      when 4 | 11 | 17 | 25 | 31 =>
        segments(C) <= '1';
        segments(D) <= '1';
        segments(e) <= '1';

      when 5 | 24 =>
        segments(C) <= '1';
        segments(D) <= '1';
        segments(G) <= '1';

      when 6 | 23 =>
        segments(C) <= '1';
        segments(F) <= '1';
        segments(G) <= '1';

      when 7 | 22 =>
        segments(A) <= '1';
        segments(F) <= '1';
        segments(G) <= '1';

      when 9 | 15 | 29 =>
        segments(A) <= '1';
        segments(B) <= '1';
        segments(C) <= '1';

      when 10 | 16 | 30 =>
        segments(B) <= '1';
        segments(C) <= '1';
        segments(D) <= '1';

      when 12 | 26 | 32 =>
        segments(D) <= '1';
        segments(E) <= '1';
        segments(F) <= '1';

      when 13 | 27 | 33 =>
        segments(A) <= '1';
        segments(E) <= '1';
        segments(F) <= '1';

      when others =>
      -- no others are possible
    
    end case;
  end process;

end architecture;