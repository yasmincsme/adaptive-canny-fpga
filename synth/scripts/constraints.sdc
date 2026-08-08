########################################################################
# constraints.sdc -- restricoes de timing para canny_top_module
#
# Ponto de partida neutro para a primeira sintese funcional. Depois de ver
# report_timing.rpt (synth/reports/), aperte create_clock e os I/O delays
# com base no caminho critico real -- nao precisa acertar de primeira.
########################################################################

# ------------------------------------------------------------------
# 1. CLOCK
# ------------------------------------------------------------------
# 10 ns = 100 MHz. Referencia de comparacao possivel: o artigo Kalbasi &
# Nikmehr (IEEE Access 2020) reporta 263 MHz num Virtex-V e 355 MHz num
# Virtex-7 para o design deles -- nao e uma meta que precisamos bater de
# cara, so contexto de ordem de grandeza para calibrar expectativa.
create_clock -name clk -period 10.0 [get_ports clk]

set_clock_uncertainty 0.5 [get_clocks clk]

# ------------------------------------------------------------------
# 2. RESET
# ------------------------------------------------------------------
# rst_n e assincrono (posedge clk or negedge rst_n em todo o datapath) --
# tirar do STA de setup/hold normal.
set_false_path -from [get_ports rst_n]

# ------------------------------------------------------------------
# 3. ATRASOS DE I/O
# ------------------------------------------------------------------
# 40% do periodo como ponto de partida, ate termos uma interface real
# (ex: vindo de outro bloco sincrono a montante/jusante).
set_input_delay  4.0 -clock clk \
    [remove_from_collection [all_inputs] [get_ports {clk rst_n}]]
set_output_delay 4.0 -clock clk [all_outputs]

# ------------------------------------------------------------------
# 4. NOTA: SINAIS QUASE-ESTATICOS
# ------------------------------------------------------------------
# HIGH_THRESH, LOW_THRESH, gauss_peso, adaptive_en, mdp e noise_threshold
# tendem a mudar raramente (ex.: reconfigurados via SPI, nao a cada
# pixel). Com I/O delay apertado como acima, eles podem dominar o
# relatorio de timing sem serem o gargalo real do datapath de pixel.
# Depois da primeira rodada, considere algo como:
#
#   set_multicycle_path -setup 4 -to [get_ports {final_pixel_out final_vld_out}] \
#       -from [get_ports {HIGH_THRESH LOW_THRESH gauss_peso}]
#
# (ajuste o multiplicador e a direcao conforme o que report_timing mostrar
# -- isto e um ponto de partida, nao uma constraint validada.)
